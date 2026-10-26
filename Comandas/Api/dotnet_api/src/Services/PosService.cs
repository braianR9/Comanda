using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace BarIceCreamShop.Api.Services;

/// Soporte de venta directa (punto de venta sin mesa/sector físico).
public class PosService(AppDbContext context)
{
    private const string SectorName = "Mostrador";
    private const string TableName = "Mostrador";

    /// Obtiene (y crea de forma perezosa si no existe) la mesa virtual de
    /// mostrador de la sucursal: admite varias ventas simultáneas y nunca
    /// se muestra en el mapa de sectores.
    public async Task<(int TableId, string TableName)> EnsureCounterTableAsync(int company, int branch)
    {
        var sector = await context.Sectors.FirstOrDefaultAsync(s => s.IdEmpresa == company && s.EsSistema)
            ?? await GetOrCreateAsync(() => CreateSectorAsync(company),
                () => context.Sectors.FirstOrDefaultAsync(s => s.IdEmpresa == company && s.EsSistema));

        var table = await context.Tables.FirstOrDefaultAsync(t => t.IdEmpresa == company && t.IdSucursal == branch && t.EsMostrador)
            ?? await GetOrCreateAsync(() => CreateTableAsync(company, branch, sector.Id),
                () => context.Tables.FirstOrDefaultAsync(t => t.IdEmpresa == company && t.IdSucursal == branch && t.EsMostrador));

        return (table.Id, table.Nombre);
    }

    /// Dos pedidos concurrentes podrían intentar crear el mismo registro
    /// "Mostrador" por primera vez; si el índice único rechaza el segundo
    /// insert, se relee lo que haya quedado creado en su lugar.
    private static async Task<T> GetOrCreateAsync<T>(Func<Task<T>> create, Func<Task<T?>> reload) where T : class
    {
        try { return await create(); }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: "23505" })
        {
            return await reload() ?? throw new SaleException("No se pudo resolver la mesa de venta directa.", 409);
        }
    }

    private async Task<Sector> CreateSectorAsync(int company)
    {
        var now = DateTime.UtcNow;
        var sector = new Sector
        {
            IdEmpresa = company, Nombre = SectorName, Descripcion = "Ventas directas de mostrador.",
            Orden = 0, Activo = true, EsSistema = true, FechaCreacion = now, FechaModificacion = now,
        };
        context.Sectors.Add(sector);
        await context.SaveChangesAsync();
        return sector;
    }

    private async Task<Table> CreateTableAsync(int company, int branch, int sectorId)
    {
        var now = DateTime.UtcNow;
        var table = new Table
        {
            IdEmpresa = company, IdSucursal = branch, SectorId = sectorId, Nombre = TableName,
            Descripcion = "Mesa virtual para venta directa.", Forma = "Rectangular", Capacidad = 1,
            PositionX = 0, PositionY = 0, Number = 0, Status = "Libre", Activo = true, EsMostrador = true,
            FechaCreacion = now, FechaModificacion = now,
        };
        context.Tables.Add(table);
        await context.SaveChangesAsync();
        return table;
    }
}
