using System.Security.Cryptography;
using System.Text;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

/// Agentes de impresión: uno por computadora del local que tenga impresoras. Con su clave, cada agente
/// pide a la API los trabajos de sus impresoras ya armados (ESC/POS) y avisa si salieron.
/// No necesita acceso a la base ni a los secretos de la API.
public sealed class PrintAgentService(AppDbContext db, PrinterConfigurationService configurations, IConfiguration configuration,
    ILogger<PrintAgentService> logger)
{
    public async Task<List<PrintAgentDto>> ListAsync(int company, int branch) =>
        await db.PrintAgents.AsNoTracking().Where(x => x.IdEmpresa == company && x.IdSucursal == branch).OrderBy(x => x.Id)
            .Select(x => new PrintAgentDto(x.Id, x.Nombre, x.FechaCreacion, x.UltimoContacto, x.Equipo)).ToListAsync();

    /// Agrega una computadora y devuelve su clave. Solo se muestra esta vez.
    public async Task<PrintAgentKeyDto> CreateAsync(int company, int branch, PrintAgentRequest request)
    {
        var agent = new PrintAgent { IdEmpresa = company, IdSucursal = branch, Nombre = await ValidName(company, branch, request.Name, null) };
        db.PrintAgents.Add(agent);
        var key = NewKey(agent);
        await db.SaveChangesAsync();
        return new PrintAgentKeyDto(agent.Id, key);
    }

    public async Task<PrintAgentDto> RenameAsync(int company, int branch, int id, PrintAgentRequest request)
    {
        var agent = await Require(company, branch, id);
        agent.Nombre = await ValidName(company, branch, request.Name, id);
        await db.SaveChangesAsync();
        return new PrintAgentDto(agent.Id, agent.Nombre, agent.FechaCreacion, agent.UltimoContacto, agent.Equipo);
    }

    /// Clave nueva para la computadora; la anterior deja de funcionar.
    public async Task<PrintAgentKeyDto> RegenerateKeyAsync(int company, int branch, int id)
    {
        var agent = await Require(company, branch, id);
        var key = NewKey(agent);
        await db.SaveChangesAsync();
        return new PrintAgentKeyDto(agent.Id, key);
    }

    /// Sus impresoras pasan a la primera computadora de la sucursal (la base las deja sin asignar).
    public async Task DeleteAsync(int company, int branch, int id)
    {
        db.PrintAgents.Remove(await Require(company, branch, id));
        await db.SaveChangesAsync();
    }

    public async Task<PrintAgent?> AuthenticateAsync(string? key, string? machine)
    {
        if (string.IsNullOrWhiteSpace(key)) return null;
        var hash = Hash(key.Trim());
        var agent = await db.PrintAgents.SingleOrDefaultAsync(x => x.ClaveHash == hash);
        if (agent == null) return null;
        // El agente consulta cada pocos segundos: el contacto se registra como mucho una vez por minuto.
        var now = DateTime.UtcNow;
        machine = string.IsNullOrWhiteSpace(machine) ? null : machine.Trim()[..Math.Min(machine.Trim().Length, 150)];
        if (agent.UltimoContacto is not { } last || now - last > TimeSpan.FromMinutes(1) || agent.Equipo != machine)
        {
            agent.UltimoContacto = now;
            agent.Equipo = machine;
            await db.SaveChangesAsync();
        }
        return agent;
    }

    /// Toma el próximo trabajo pendiente de las impresoras de esta computadora; null si no hay.
    public async Task<PrintAgentJobDto?> NextAsync(PrintAgent agent, CancellationToken cancellationToken)
    {
        await AssignPrintersAsync(agent, cancellationToken);
        var firstAgentId = await db.PrintAgents.Where(x => x.IdEmpresa == agent.IdEmpresa && x.IdSucursal == agent.IdSucursal)
            .OrderBy(x => x.Id).Select(x => x.Id).FirstAsync(cancellationToken);
        var isFirst = firstAgentId == agent.Id;
        // Las impresoras sin computadora asignada (y los trabajos sin impresora) los imprime la primera.
        var mine = PrintJobWorker.Jobs(db, agent.IdSucursal).Where(x => x.PrinterConfigurationId == null
            ? isFirst
            : db.PrinterConfigurations.Any(p => p.Id == x.PrinterConfigurationId
                && (p.IdAgente == agent.Id || (p.IdAgente == null && isFirst))));
        while (true)
        {
            var job = await mine.OrderBy(x => x.CreatedAt).FirstOrDefaultAsync(cancellationToken);
            if (job == null) return null;
            // Otro pedido de un agente pudo tomarlo en el medio.
            var taken = await db.PrintJobs.Where(x => x.Id == job.Id && x.Status == "Pendiente")
                .ExecuteUpdateAsync(x => x.SetProperty(j => j.Status, "Procesando"), cancellationToken);
            if (taken == 0) { db.Entry(job).State = EntityState.Detached; continue; }
            job.Status = "Procesando";
            try
            {
                var (printer, ticket) = await PrintJobWorker.RenderAsync(db, configurations, configuration, job, cancellationToken);
                await db.SaveChangesAsync(cancellationToken);
                return new PrintAgentJobDto(job.Id, job.JobType,
                    new PrintAgentPrinterDto(printer.Nombre, printer.TipoConexion, printer.NombreCola, printer.DireccionIp, printer.Puerto),
                    Convert.ToBase64String(ticket));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                job.Status = "Error";
                await db.SaveChangesAsync(cancellationToken);
                logger.LogError(ex, "No se pudo armar el trabajo de impresión {PrintJobId}.", job.Id);
            }
        }
    }

    public async Task<bool> ResultAsync(PrintAgent agent, int jobId, PrintAgentResultRequest request)
    {
        var job = await PrintJobWorker.Jobs(db, agent.IdSucursal, "Procesando").SingleOrDefaultAsync(x => x.Id == jobId);
        if (job == null) return false;
        job.Status = request.Ok ? "Impreso" : "Error";
        await db.SaveChangesAsync();
        if (!request.Ok)
            logger.LogError("El agente {AgentName} de la sucursal {BranchId} no pudo imprimir el trabajo {PrintJobId}: {Error}",
                agent.Nombre, agent.IdSucursal, jobId, request.Error);
        return true;
    }

    /// Tickets y cierres de caja se encolan sin impresora: se resuelve antes de repartirlos entre computadoras.
    private async Task AssignPrintersAsync(PrintAgent agent, CancellationToken cancellationToken)
    {
        var jobs = await PrintJobWorker.Jobs(db, agent.IdSucursal).Where(x => x.PrinterConfigurationId == null).ToListAsync(cancellationToken);
        foreach (var job in jobs)
        {
            var printer = await configurations.ResolveAsync(agent.IdEmpresa, agent.IdSucursal,
                job.JobType == "CierreCaja" ? "TicketVenta" : job.JobType);
            if (printer != null) job.PrinterConfigurationId = printer.Id;
        }
        if (jobs.Count > 0) await db.SaveChangesAsync(cancellationToken);
    }

    private async Task<string> ValidName(int company, int branch, string? name, int? exceptId)
    {
        name = name?.Trim() ?? "";
        if (name.Length is < 1 or > 100) throw new SaleException("Indicá un nombre para la computadora.");
        if (await db.PrintAgents.AnyAsync(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Id != exceptId && x.Nombre.ToLower() == name.ToLower()))
            throw new SaleException("Ya hay una computadora con ese nombre.", 409);
        return name;
    }

    private async Task<PrintAgent> Require(int company, int branch, int id) =>
        await db.PrintAgents.SingleOrDefaultAsync(x => x.Id == id && x.IdEmpresa == company && x.IdSucursal == branch)
        ?? throw new SaleException("Computadora no encontrada.", 404);

    private static string NewKey(PrintAgent agent)
    {
        var key = "foco_" + Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        agent.ClaveHash = Hash(key);
        agent.FechaCreacion = DateTime.UtcNow;
        agent.UltimoContacto = null;
        agent.Equipo = null;
        return key;
    }

    private static string Hash(string key) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
}
