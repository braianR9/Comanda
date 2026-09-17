using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class PrinterConfigurationService(AppDbContext db, PrinterTransport transport)
{
    public async Task<List<PrinterConfigurationDto>> ListAsync(int company, int branch, bool includeInactive) =>
        await db.PrinterConfigurations.AsNoTracking()
            .Where(x => x.IdEmpresa == company && x.IdSucursal == branch && (includeInactive || x.Activa))
            .OrderByDescending(x => x.Predeterminada).ThenBy(x => x.Nombre)
            .Select(x => ToDto(x)).ToListAsync();

    public async Task<PrinterConfigurationDto?> GetAsync(int company, int branch, int id) =>
        await db.PrinterConfigurations.AsNoTracking().Where(x => x.Id == id && x.IdEmpresa == company && x.IdSucursal == branch).Select(x => ToDto(x)).SingleOrDefaultAsync();

    public async Task<PrinterConfigurationDto> CreateAsync(int company, int branch, PrinterConfigurationRequest request)
    {
        Validate(request);
        var name = request.Name.Trim();
        if (await db.PrinterConfigurations.AnyAsync(x => x.IdSucursal == branch && x.Nombre.ToLower() == name.ToLower())) throw new SaleException("Ya existe una impresora con ese nombre.", 409);
        var value = new PrinterConfiguration { IdEmpresa = company, IdSucursal = branch, FechaCreacion = DateTime.UtcNow };
        Apply(value, request);
        if (value.Predeterminada) await ClearOverlappingDefaults(company, branch, value.Uso, null);
        db.PrinterConfigurations.Add(value); await db.SaveChangesAsync(); return ToDto(value);
    }

    public async Task<PrinterConfigurationDto> UpdateAsync(int company, int branch, int id, PrinterConfigurationRequest request)
    {
        Validate(request);
        var value = await Require(company, branch, id);
        var name = request.Name.Trim();
        if (await db.PrinterConfigurations.AnyAsync(x => x.IdSucursal == branch && x.Id != id && x.Nombre.ToLower() == name.ToLower())) throw new SaleException("Ya existe una impresora con ese nombre.", 409);
        Apply(value, request);
        if (value.Predeterminada) await ClearOverlappingDefaults(company, branch, value.Uso, id);
        await db.SaveChangesAsync(); return ToDto(value);
    }

    public async Task<PrinterConfigurationDto> SetStatusAsync(int company, int branch, int id, bool active)
    { var value = await Require(company, branch, id); value.Activa = active; if (!active) value.Predeterminada = false; value.FechaModificacion = DateTime.UtcNow; await db.SaveChangesAsync(); return ToDto(value); }

    public async Task TestAsync(int company, int branch, int id, CancellationToken cancellationToken)
    { var value = await Require(company, branch, id); if (!value.Activa) throw new SaleException("La impresora está inactiva.", 409); await transport.TestAsync(value, cancellationToken); }

    public async Task<PrinterConfiguration?> ResolveAsync(int company, int branch, string usage) =>
        await db.PrinterConfigurations.AsNoTracking().Where(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Activa && (x.Uso == usage || x.Uso == "Ambos"))
            .OrderByDescending(x => x.Predeterminada).ThenBy(x => x.Uso == usage ? 0 : 1).ThenBy(x => x.Id).FirstOrDefaultAsync();

    private async Task<PrinterConfiguration> Require(int company, int branch, int id) => await db.PrinterConfigurations.SingleOrDefaultAsync(x => x.Id == id && x.IdEmpresa == company && x.IdSucursal == branch) ?? throw new SaleException("Impresora no encontrada.", 404);
    private async Task ClearOverlappingDefaults(int company, int branch, string usage, int? exceptId)
    {
        var values = await db.PrinterConfigurations.Where(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Id != exceptId && x.Predeterminada && (x.Uso == usage || x.Uso == "Ambos" || usage == "Ambos")).ToListAsync();
        foreach (var value in values) { value.Predeterminada = false; value.FechaModificacion = DateTime.UtcNow; }
    }
    private static void Apply(PrinterConfiguration value, PrinterConfigurationRequest request)
    { value.Nombre = request.Name.Trim(); value.TipoConexion = request.ConnectionType; value.NombreCola = request.ConnectionType == "Cups" ? request.QueueName?.Trim() : null; value.DireccionIp = request.ConnectionType == "Red" ? request.IpAddress?.Trim() : null; value.Puerto = request.ConnectionType == "Red" ? request.Port : null; value.Uso = request.Usage; value.Predeterminada = request.IsDefault; value.Activa = request.Active; value.FechaModificacion = DateTime.UtcNow; }
    private static void Validate(PrinterConfigurationRequest request)
    { if (string.IsNullOrWhiteSpace(request.Name)) throw new SaleException("El nombre es obligatorio."); if (request.ConnectionType is not ("Cups" or "Red")) throw new SaleException("La conexión debe ser Cups o Red."); if (request.Usage is not ("Comanda" or "TicketVenta" or "Ambos")) throw new SaleException("El uso debe ser Comanda, TicketVenta o Ambos."); if (request.ConnectionType == "Cups" && string.IsNullOrWhiteSpace(request.QueueName)) throw new SaleException("El nombre de la cola CUPS es obligatorio."); if (request.ConnectionType == "Red" && (string.IsNullOrWhiteSpace(request.IpAddress) || request.Port is null or < 1 or > 65535)) throw new SaleException("La IP y el puerto son obligatorios para una impresora de red."); }
    private static PrinterConfigurationDto ToDto(PrinterConfiguration x) => new(x.Id, x.Nombre, x.TipoConexion, x.NombreCola, x.DireccionIp, x.Puerto, x.Uso, x.Predeterminada, x.Activa);
}
