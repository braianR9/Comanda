using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class SectorException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class SectorService
{
    private readonly AppDbContext _context;
    public SectorService(AppDbContext context) => _context = context;

    public async Task<List<SectorDto>> GetAllAsync(int company, bool? active, string? text)
    {
        var query = _context.Sectors.AsNoTracking().Where(s => s.IdEmpresa == company);
        if (active.HasValue) query = query.Where(s => s.Activo == active.Value);
        if (!string.IsNullOrWhiteSpace(text)) query = query.Where(s => EF.Functions.ILike(s.Nombre, $"%{text.Trim()}%"));
        return await query.OrderBy(s => s.Orden).ThenBy(s => s.Nombre).Select(s => new SectorDto
        {
            Id = s.Id, Name = s.Nombre, Description = s.Descripcion, Order = s.Orden,
            Active = s.Activo, CreatedAt = s.FechaCreacion, UpdatedAt = s.FechaModificacion
        }).ToListAsync();
    }

    public async Task<SectorDto?> GetAsync(int company, int id) => await _context.Sectors.AsNoTracking()
        .Where(s => s.IdEmpresa == company && s.Id == id).Select(s => new SectorDto
        {
            Id = s.Id, Name = s.Nombre, Description = s.Descripcion, Order = s.Orden,
            Active = s.Activo, CreatedAt = s.FechaCreacion, UpdatedAt = s.FechaModificacion
        }).FirstOrDefaultAsync();

    public async Task<SectorDto> CreateAsync(int company, SectorRequest request)
    {
        var name = Validate(request); await EnsureUniqueName(company, name, null); var now = DateTime.UtcNow;
        var entity = new Sector { IdEmpresa = company, Nombre = name, Descripcion = request.Description.Trim(), Orden = request.Order, Activo = true, FechaCreacion = now, FechaModificacion = now };
        _context.Sectors.Add(entity); await _context.SaveChangesAsync(); return Map(entity);
    }

    public async Task<SectorDto> UpdateAsync(int company, int id, SectorRequest request)
    {
        var entity = await Entity(company, id); var name = Validate(request); await EnsureUniqueName(company, name, id);
        entity.Nombre = name; entity.Descripcion = request.Description.Trim(); entity.Orden = request.Order; entity.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync(); return Map(entity);
    }

    public async Task<SectorDto> SetStatusAsync(int company, int id, bool active)
    {
        var entity = await Entity(company, id); entity.Activo = active; entity.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync(); return Map(entity);
    }

    public async Task DeleteAsync(int company, int id)
    {
        var entity = await Entity(company, id); entity.Activo = false; entity.FechaModificacion = DateTime.UtcNow; await _context.SaveChangesAsync();
    }

    public async Task<List<SectorDto>> ReorderAsync(int company, ReorderSectorsRequest request)
    {
        if (request.Items.Select(i => i.Id).Distinct().Count() != request.Items.Count) throw new SectorException("No se puede repetir un sector en el ordenamiento.");
        var ids = request.Items.Select(i => i.Id).ToList();
        var sectors = await _context.Sectors.Where(s => s.IdEmpresa == company && ids.Contains(s.Id)).ToListAsync();
        if (sectors.Count != ids.Count) throw new SectorException("Uno o más sectores no existen o no pertenecen a la empresa.", 404);
        var orders = request.Items.ToDictionary(i => i.Id, i => i.Order); var now = DateTime.UtcNow;
        foreach (var sector in sectors) { sector.Orden = orders[sector.Id]; sector.FechaModificacion = now; }
        await _context.SaveChangesAsync(); return sectors.OrderBy(s => s.Orden).ThenBy(s => s.Nombre).Select(Map).ToList();
    }

    private static string Validate(SectorRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name)) throw new SectorException("El nombre es obligatorio.");
        if (string.IsNullOrWhiteSpace(request.Description)) throw new SectorException("La descripción es obligatoria.");
        if (request.Order < 0) throw new SectorException("El orden no puede ser negativo.");
        return request.Name.Trim();
    }
    private async Task EnsureUniqueName(int company, string name, int? except) { if (await _context.Sectors.AnyAsync(s => s.IdEmpresa == company && s.Id != except && s.Nombre.ToLower() == name.ToLower())) throw new SectorException("Ya existe un sector con ese nombre.", 409); }
    private async Task<Sector> Entity(int company, int id) => await _context.Sectors.FirstOrDefaultAsync(s => s.IdEmpresa == company && s.Id == id) ?? throw new SectorException("Sector no encontrado.", 404);
    private static SectorDto Map(Sector s) => new() { Id = s.Id, Name = s.Nombre, Description = s.Descripcion, Order = s.Orden, Active = s.Activo, CreatedAt = s.FechaCreacion, UpdatedAt = s.FechaModificacion };
}
