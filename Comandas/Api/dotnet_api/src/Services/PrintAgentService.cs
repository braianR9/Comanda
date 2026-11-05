using System.Security.Cryptography;
using System.Text;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

/// Agente de impresión del local: con su clave pide los trabajos de su sucursal ya armados
/// (ESC/POS) y avisa si salieron. No necesita acceso a la base ni a los secretos de la API.
public sealed class PrintAgentService(AppDbContext db, PrinterConfigurationService configurations, IConfiguration configuration,
    ILogger<PrintAgentService> logger)
{
    public async Task<PrintAgentStatusDto> StatusAsync(int company, int branch)
    {
        var agent = await db.PrintAgents.AsNoTracking().SingleOrDefaultAsync(x => x.IdEmpresa == company && x.IdSucursal == branch);
        return new PrintAgentStatusDto(agent != null, agent?.FechaCreacion, agent?.UltimoContacto, agent?.Equipo);
    }

    /// Genera una clave nueva para la sucursal; la anterior deja de funcionar. Solo se muestra esta vez.
    public async Task<PrintAgentKeyDto> CreateKeyAsync(int company, int branch)
    {
        var key = "foco_" + Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        var agent = await db.PrintAgents.SingleOrDefaultAsync(x => x.IdEmpresa == company && x.IdSucursal == branch);
        if (agent == null) db.PrintAgents.Add(agent = new PrintAgent { IdEmpresa = company, IdSucursal = branch });
        agent.ClaveHash = Hash(key);
        agent.FechaCreacion = DateTime.UtcNow;
        agent.UltimoContacto = null;
        agent.Equipo = null;
        await db.SaveChangesAsync();
        return new PrintAgentKeyDto(key);
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

    /// Toma el próximo trabajo pendiente de la sucursal; null si no hay.
    public async Task<PrintAgentJobDto?> NextAsync(PrintAgent agent, CancellationToken cancellationToken)
    {
        while (true)
        {
            var job = await PrintJobWorker.Jobs(db, agent.IdSucursal).OrderBy(x => x.CreatedAt).FirstOrDefaultAsync(cancellationToken);
            if (job == null) return null;
            // Otro pedido del agente pudo tomarlo en el medio.
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
            logger.LogError("El agente de la sucursal {BranchId} no pudo imprimir el trabajo {PrintJobId}: {Error}",
                agent.IdSucursal, jobId, request.Error);
        return true;
    }

    private static string Hash(string key) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
}
