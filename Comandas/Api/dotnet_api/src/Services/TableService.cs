using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class TableException(string message, int statusCode = 400) : Exception(message) { public int StatusCode { get; } = statusCode; }

public class TableService(AppDbContext context)
{
    private static readonly HashSet<string> Shapes = new(StringComparer.OrdinalIgnoreCase) { "Circular", "Cuadrada", "Rectangular" };

    public async Task<List<TableDto>> GetAllAsync(int company, int branch, int? sectorId, bool? active)
    {
        var query = context.Tables.AsNoTracking().Include(t => t.Sector).Where(t => t.IdEmpresa == company && t.IdSucursal == branch);
        if (sectorId.HasValue) query = query.Where(t => t.SectorId == sectorId);
        if (active.HasValue) query = query.Where(t => t.Activo == active);
        return (await query.OrderBy(t => t.Sector.Orden).ThenBy(t => t.Nombre).ToListAsync()).Select(Map).ToList();
    }

    public async Task<TableDto?> GetAsync(int company, int branch, int id)
    {
        var value = await context.Tables.AsNoTracking().Include(t => t.Sector).FirstOrDefaultAsync(t => t.Id == id && t.IdEmpresa == company && t.IdSucursal == branch);
        return value == null ? null : Map(value);
    }

    public async Task<TableDto> CreateAsync(int company, int branch, TableRequest request)
    {
        var name = await Validate(company, branch, request, null); var now = DateTime.UtcNow;
        var value = new Table { IdEmpresa = company, IdSucursal = branch, SectorId = request.SectorId, Nombre = name, Descripcion = CleanDescription(request.Description), Forma = Normalize(ShapeFrom(request)), Capacidad = request.Capacity, PositionX = RoundPosition(request.PositionX), PositionY = RoundPosition(request.PositionY), Status = "Libre", Activo = true, FechaCreacion = now, FechaModificacion = now };
        context.Tables.Add(value); await context.SaveChangesAsync(); return (await GetAsync(company, branch, value.Id))!;
    }

    public async Task<TableDto> UpdateAsync(int company, int branch, int id, TableRequest request)
    {
        var value = await Entity(company, branch, id); var name = await Validate(company, branch, request, id);
        value.SectorId = request.SectorId; value.Nombre = name; value.Descripcion = CleanDescription(request.Description); value.Forma = Normalize(ShapeFrom(request)); value.Capacidad = request.Capacity; value.PositionX = RoundPosition(request.PositionX); value.PositionY = RoundPosition(request.PositionY); value.FechaModificacion = DateTime.UtcNow;
        await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<TableDto> SetActiveAsync(int company, int branch, int id, bool active) { var value = await Entity(company, branch, id); value.Activo = active; value.FechaModificacion = DateTime.UtcNow; await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!; }
    public async Task DeleteAsync(int company, int branch, int id) { var value = await Entity(company, branch, id); value.Activo = false; value.FechaModificacion = DateTime.UtcNow; await context.SaveChangesAsync(); }

    private async Task<string> Validate(int company, int branch, TableRequest request, int? except)
    {
        if (string.IsNullOrWhiteSpace(request.Name)) throw new TableException("El nombre es obligatorio.");
        if (request.Capacity <= 0) throw new TableException("La capacidad debe ser mayor que cero.");
        if (request.PositionX is < 0 or > 1 || request.PositionY is < 0 or > 1) throw new TableException("positionX y positionY deben estar entre 0 y 1.");
        if (!Shapes.Contains(ShapeFrom(request))) throw new TableException("La forma debe ser Circular, Cuadrada o Rectangular.");
        if (!await context.Sectors.AnyAsync(s => s.Id == request.SectorId && s.IdEmpresa == company && s.Activo)) throw new TableException("El sector no existe, está inactivo o pertenece a otra empresa.");
        var name = request.Name.Trim();
        if (await context.Tables.AnyAsync(t => t.IdEmpresa == company && t.IdSucursal == branch && t.Id != except && t.Nombre.ToLower() == name.ToLower())) throw new TableException("Ya existe una mesa con ese nombre en la sucursal.", 409);
        return name;
    }

    private async Task<Table> Entity(int company, int branch, int id) => await context.Tables.FirstOrDefaultAsync(t => t.Id == id && t.IdEmpresa == company && t.IdSucursal == branch) ?? throw new TableException("Mesa no encontrada.", 404);
    private static string ShapeFrom(TableRequest request) => string.IsNullOrWhiteSpace(request.Type) ? (request.Shape ?? string.Empty).Trim() : request.Type.Trim();
    private static string Normalize(string shape) => Shapes.First(t => t.Equals(shape, StringComparison.OrdinalIgnoreCase));
    private static decimal RoundPosition(decimal value) => decimal.Round(value, 6, MidpointRounding.AwayFromZero);
    private static string? CleanDescription(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static TableDto Map(Table t) => new() { Id = t.Id, Name = t.Nombre, Description = t.Descripcion, SectorId = t.SectorId, Sector = new SectorDto { Id = t.Sector.Id, Name = t.Sector.Nombre, Description = t.Sector.Descripcion, Order = t.Sector.Orden, Active = t.Sector.Activo, CreatedAt = t.Sector.FechaCreacion, UpdatedAt = t.Sector.FechaModificacion }, Shape = t.Forma, Capacity = t.Capacidad, PositionX = t.PositionX, PositionY = t.PositionY, Status = t.Status, Active = t.Activo };
}
