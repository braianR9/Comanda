using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class CatalogoException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class CatalogosService
{
    private readonly AppDbContext _context;
    public CatalogosService(AppDbContext context) => _context = context;

    public async Task<List<RubroDto>> GetRubrosAsync(int company, string? text, bool? active)
    {
        var query = _context.Rubros.AsNoTracking().Where(r => r.IdEmpresa == company);
        query = active.HasValue ? query.Where(r => r.Activo == active) : query.Where(r => r.Activo);
        if (!string.IsNullOrWhiteSpace(text)) query = query.Where(r => EF.Functions.ILike(r.Nombre, $"%{text.Trim()}%"));
        var rubros = await query.OrderBy(r => r.Nombre).Select(r => new RubroDto
        {
            Id = r.Id, Nombre = r.Nombre, Descripcion = r.Descripcion,
            TipoObservacion = r.TipoObservacion, ImagenUrl = r.ImagenUrl,
            AplicarProductos = r.AplicarProductos, AplicarDelivery = r.AplicarDelivery,
            AplicarSalon = r.AplicarSalon, MostrarCartaDigital = r.MostrarCartaDigital,
            Activo = r.Activo
        }).ToListAsync();

        var rubroIds = rubros.Select(r => r.Id).ToList();
        var subRubros = await _context.SubRubros.AsNoTracking()
            .Where(s => s.IdEmpresa == company && rubroIds.Contains(s.IdRubro) && s.Activo)
            .OrderBy(s => s.Nombre)
            .Select(s => new SubRubroDto
            {
                Id = s.Id, IdRubro = s.IdRubro, Nombre = s.Nombre, Descripcion = s.Descripcion,
                TipoObservacion = s.TipoObservacion, ImagenUrl = s.ImagenUrl,
                AplicarProductos = s.AplicarProductos, AplicarIngredientes = s.AplicarIngredientes,
                AplicarDelivery = s.AplicarDelivery, AplicarSalon = s.AplicarSalon,
                MostrarCartaDigital = s.MostrarCartaDigital, Activo = s.Activo
            }).ToListAsync();
        var byRubro = subRubros.GroupBy(s => s.IdRubro).ToDictionary(g => g.Key, g => (IReadOnlyList<SubRubroDto>)g.ToList());
        foreach (var rubro in rubros)
            rubro.SubRubros = byRubro.GetValueOrDefault(rubro.Id, []);
        return rubros;
    }

    public async Task<RubroDto?> GetRubroAsync(int company, int id)
    {
        var rubro = await _context.Rubros.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id && r.IdEmpresa == company);
        if (rubro == null) return null;
        return new RubroDto
        {
            Id = rubro.Id, Nombre = rubro.Nombre, Descripcion = rubro.Descripcion,
            TipoObservacion = rubro.TipoObservacion, ImagenUrl = rubro.ImagenUrl,
            AplicarProductos = rubro.AplicarProductos, AplicarDelivery = rubro.AplicarDelivery,
            AplicarSalon = rubro.AplicarSalon, MostrarCartaDigital = rubro.MostrarCartaDigital,
            Activo = rubro.Activo,
            SubRubros = await _context.SubRubros.AsNoTracking().Where(s => s.IdRubro == id && s.IdEmpresa == company)
                .OrderBy(s => s.Nombre).Select(s => new SubRubroDto
                {
                    Id = s.Id, IdRubro = s.IdRubro, Nombre = s.Nombre, Descripcion = s.Descripcion,
                    TipoObservacion = s.TipoObservacion, ImagenUrl = s.ImagenUrl,
                    AplicarProductos = s.AplicarProductos, AplicarIngredientes = s.AplicarIngredientes,
                    AplicarDelivery = s.AplicarDelivery, AplicarSalon = s.AplicarSalon,
                    MostrarCartaDigital = s.MostrarCartaDigital, Activo = s.Activo
                }).ToListAsync()
        };
    }

    public async Task<RubroDto> CreateRubroAsync(int company, RubroRequest request)
    {
        var name = RequiredName(request.Nombre);
        if (await _context.Rubros.AnyAsync(r => r.IdEmpresa == company && r.Nombre.ToLower() == name.ToLower()))
            throw new CatalogoException("Ya existe un rubro con ese nombre.", 409);
        var entity = new Rubro { IdEmpresa = company, Activo = true };
        ApplyRubro(entity, request, name);
        _context.Rubros.Add(entity); await _context.SaveChangesAsync();
        return Map(entity);
    }

    public async Task<RubroDto> UpdateRubroAsync(int company, int id, RubroRequest request)
    {
        var entity = await RubroEntity(company, id); var name = RequiredName(request.Nombre);
        if (await _context.Rubros.AnyAsync(r => r.IdEmpresa == company && r.Id != id && r.Nombre.ToLower() == name.ToLower()))
            throw new CatalogoException("Ya existe un rubro con ese nombre.", 409);
        ApplyRubro(entity, request, name); await _context.SaveChangesAsync();
        return Map(entity);
    }

    public async Task SetRubroStatusAsync(int company, int id, bool active) { var e = await RubroEntity(company, id); e.Activo = active; await _context.SaveChangesAsync(); }
    public Task<Rubro> GetRubroEntityAsync(int company, int id) => RubroEntity(company, id);
    public Task SaveAsync() => _context.SaveChangesAsync();
    public async Task DeleteRubroAsync(int company, int id)
    {
        var e = await RubroEntity(company, id);
        if (await _context.Productos.AnyAsync(p => p.IdEmpresa == company && p.IdRubro == id) || await _context.SubRubros.AnyAsync(s => s.IdEmpresa == company && s.IdRubro == id))
            throw new CatalogoException("No se puede eliminar el rubro porque tiene productos o subrubros relacionados.", 409);
        _context.Rubros.Remove(e); await _context.SaveChangesAsync();
    }

    public async Task<List<SubRubroDto>> GetSubRubrosAsync(int company, int rubroId, bool? active)
    {
        await RubroEntity(company, rubroId);
        var query = _context.SubRubros.AsNoTracking().Where(s => s.IdEmpresa == company && s.IdRubro == rubroId);
        query = active.HasValue ? query.Where(s => s.Activo == active) : query.Where(s => s.Activo);
        return await query.OrderBy(s => s.Nombre).Select(s => new SubRubroDto
        {
            Id = s.Id, IdRubro = s.IdRubro, Nombre = s.Nombre, Descripcion = s.Descripcion,
            TipoObservacion = s.TipoObservacion, ImagenUrl = s.ImagenUrl,
            AplicarProductos = s.AplicarProductos, AplicarIngredientes = s.AplicarIngredientes,
            AplicarDelivery = s.AplicarDelivery, AplicarSalon = s.AplicarSalon,
            MostrarCartaDigital = s.MostrarCartaDigital, Activo = s.Activo
        }).ToListAsync();
    }

    public async Task<SubRubroDto?> GetSubRubroAsync(int company, int id) => await _context.SubRubros.AsNoTracking()
        .Where(s => s.IdEmpresa == company && s.Id == id)
        .Select(s => new SubRubroDto
        {
            Id = s.Id, IdRubro = s.IdRubro, Nombre = s.Nombre, Descripcion = s.Descripcion,
            TipoObservacion = s.TipoObservacion, ImagenUrl = s.ImagenUrl,
            AplicarProductos = s.AplicarProductos, AplicarIngredientes = s.AplicarIngredientes,
            AplicarDelivery = s.AplicarDelivery, AplicarSalon = s.AplicarSalon,
            MostrarCartaDigital = s.MostrarCartaDigital, Activo = s.Activo
        }).FirstOrDefaultAsync();

    public async Task<SubRubroDto> CreateSubRubroAsync(int company, int rubroId, SubRubroRequest request)
    {
        await RubroEntity(company, rubroId); var name = RequiredName(request.Nombre);
        if (await _context.SubRubros.AnyAsync(s => s.IdRubro == rubroId && s.Nombre.ToLower() == name.ToLower()))
            throw new CatalogoException("Ya existe un subrubro con ese nombre dentro del rubro.", 409);
        var e = new SubRubro { IdEmpresa = company, IdRubro = rubroId, Activo = true };
        ApplySubRubro(e, request, name);
        _context.SubRubros.Add(e); await _context.SaveChangesAsync(); return Map(e);
    }

    public async Task<SubRubroDto> UpdateSubRubroAsync(int company, int id, UpdateSubRubroRequest request)
    {
        var e = await SubRubroEntity(company, id); await RubroEntity(company, request.IdRubro); var name = RequiredName(request.Nombre);
        if (await _context.SubRubros.AnyAsync(s => s.IdRubro == request.IdRubro && s.Id != id && s.Nombre.ToLower() == name.ToLower()))
            throw new CatalogoException("Ya existe un subrubro con ese nombre dentro del rubro.", 409);
        if (e.IdRubro != request.IdRubro && await _context.Productos.AnyAsync(p => p.IdEmpresa == company && p.IdSubRubro == id))
            throw new CatalogoException("No se puede cambiar el rubro de un subrubro utilizado por productos.", 409);
        e.IdRubro = request.IdRubro; ApplySubRubro(e, request, name); await _context.SaveChangesAsync(); return Map(e);
    }

    public async Task SetSubRubroStatusAsync(int company, int id, bool active) { var e = await SubRubroEntity(company, id); e.Activo = active; await _context.SaveChangesAsync(); }
    public Task<SubRubro> GetSubRubroEntityAsync(int company, int id) => SubRubroEntity(company, id);
    public async Task DeleteSubRubroAsync(int company, int id)
    {
        var e = await SubRubroEntity(company, id);
        if (await _context.Productos.AnyAsync(p => p.IdEmpresa == company && p.IdSubRubro == id)) throw new CatalogoException("El subrubro está utilizado por productos.", 409);
        _context.SubRubros.Remove(e); await _context.SaveChangesAsync();
    }

    public async Task<List<AlicuotaDto>> GetAlicuotasAsync(int company, bool? active)
    {
        var query = _context.Alicuotas.AsNoTracking().Where(a => a.IdEmpresa == null || a.IdEmpresa == company);
        query = active.HasValue ? query.Where(a => a.Activa == active) : query.Where(a => a.Activa);
        return await query.OrderBy(a => a.Porcentaje).Select(a => new AlicuotaDto { Id = a.Id, Nombre = a.Nombre, Descripcion = a.Descripcion, Porcentaje = a.Porcentaje, Activa = a.Activa, Global = a.IdEmpresa == null }).ToListAsync();
    }

    public async Task<AlicuotaDto?> GetAlicuotaAsync(int company, int id) => await _context.Alicuotas.AsNoTracking()
        .Where(a => a.Id == id && (a.IdEmpresa == null || a.IdEmpresa == company))
        .Select(a => new AlicuotaDto { Id = a.Id, Nombre = a.Nombre, Descripcion = a.Descripcion, Porcentaje = a.Porcentaje, Activa = a.Activa, Global = a.IdEmpresa == null }).FirstOrDefaultAsync();

    public async Task<AlicuotaDto> CreateAlicuotaAsync(int company, AlicuotaRequest request)
    {
        ValidateAlicuota(request); await EnsureAlicuotaName(company, request.Nombre, null);
        var e = new Alicuota { IdEmpresa = company, Nombre = request.Nombre.Trim(), Descripcion = request.Descripcion.Trim(), Porcentaje = decimal.Round(request.Porcentaje, 2), Activa = true };
        _context.Alicuotas.Add(e); await _context.SaveChangesAsync(); return Map(e);
    }

    public async Task<AlicuotaDto> UpdateAlicuotaAsync(int company, int id, AlicuotaRequest request)
    {
        var e = await AlicuotaEntity(company, id); ValidateAlicuota(request); await EnsureAlicuotaName(company, request.Nombre, id);
        e.Nombre = request.Nombre.Trim(); e.Descripcion = request.Descripcion.Trim(); e.Porcentaje = decimal.Round(request.Porcentaje, 2);
        await _context.SaveChangesAsync(); return Map(e);
    }

    public async Task SetAlicuotaStatusAsync(int company, int id, bool active) { var e = await AlicuotaEntity(company, id); e.Activa = active; await _context.SaveChangesAsync(); }
    public async Task DeleteAlicuotaAsync(int company, int id)
    {
        var e = await AlicuotaEntity(company, id);
        if (await _context.Productos.AnyAsync(p => p.IdEmpresa == company && p.IdAlicuota == id)) throw new CatalogoException("La alícuota está utilizada por productos.", 409);
        _context.Alicuotas.Remove(e); await _context.SaveChangesAsync();
    }

    private async Task<Rubro> RubroEntity(int company, int id) => await _context.Rubros.FirstOrDefaultAsync(r => r.IdEmpresa == company && r.Id == id) ?? throw new CatalogoException("Rubro no encontrado.", 404);
    private async Task<SubRubro> SubRubroEntity(int company, int id) => await _context.SubRubros.FirstOrDefaultAsync(s => s.IdEmpresa == company && s.Id == id) ?? throw new CatalogoException("Subrubro no encontrado.", 404);
    private async Task<Alicuota> AlicuotaEntity(int company, int id) => await _context.Alicuotas.FirstOrDefaultAsync(a => a.IdEmpresa == company && a.Id == id) ?? throw new CatalogoException("Alícuota no encontrada o global de solo lectura.", 404);
    private static string RequiredName(string name) => string.IsNullOrWhiteSpace(name) ? throw new CatalogoException("El nombre es obligatorio.") : name.Trim();
    private static SubRubroDto Map(SubRubro e) => new()
    {
        Id = e.Id, IdRubro = e.IdRubro, Nombre = e.Nombre, Descripcion = e.Descripcion,
        TipoObservacion = e.TipoObservacion, ImagenUrl = e.ImagenUrl,
        AplicarProductos = e.AplicarProductos, AplicarIngredientes = e.AplicarIngredientes,
        AplicarDelivery = e.AplicarDelivery, AplicarSalon = e.AplicarSalon,
        MostrarCartaDigital = e.MostrarCartaDigital, Activo = e.Activo
    };
    private static void ApplySubRubro(SubRubro e, SubRubroRequest r, string name)
    {
        e.Nombre = name; e.Descripcion = string.IsNullOrWhiteSpace(r.Descripcion) ? null : r.Descripcion.Trim();
        e.TipoObservacion = string.IsNullOrWhiteSpace(r.TipoObservacion) ? "SinObservaciones" : r.TipoObservacion.Trim();
        e.AplicarProductos = r.AplicarProductos; e.AplicarIngredientes = r.AplicarIngredientes;
        e.AplicarDelivery = r.AplicarDelivery; e.AplicarSalon = r.AplicarSalon;
        e.MostrarCartaDigital = r.MostrarCartaDigital;
    }
    private static RubroDto Map(Rubro e) => new()
    {
        Id = e.Id, Nombre = e.Nombre, Descripcion = e.Descripcion,
        TipoObservacion = e.TipoObservacion, ImagenUrl = e.ImagenUrl,
        AplicarProductos = e.AplicarProductos, AplicarDelivery = e.AplicarDelivery,
        AplicarSalon = e.AplicarSalon, MostrarCartaDigital = e.MostrarCartaDigital,
        Activo = e.Activo
    };
    private static void ApplyRubro(Rubro e, RubroRequest r, string name)
    {
        e.Nombre = name;
        e.Descripcion = string.IsNullOrWhiteSpace(r.Descripcion) ? null : r.Descripcion.Trim();
        e.TipoObservacion = string.IsNullOrWhiteSpace(r.TipoObservacion) ? "SinObservaciones" : r.TipoObservacion.Trim();
        e.AplicarProductos = r.AplicarProductos;
        e.AplicarDelivery = r.AplicarDelivery;
        e.AplicarSalon = r.AplicarSalon;
        e.MostrarCartaDigital = r.MostrarCartaDigital;
    }
    private static AlicuotaDto Map(Alicuota e) => new() { Id = e.Id, Nombre = e.Nombre, Descripcion = e.Descripcion, Porcentaje = e.Porcentaje, Activa = e.Activa, Global = e.IdEmpresa == null };
    private static void ValidateAlicuota(AlicuotaRequest r) { RequiredName(r.Nombre); if (string.IsNullOrWhiteSpace(r.Descripcion)) throw new CatalogoException("La descripción es obligatoria."); if (r.Porcentaje is < 0 or > 100) throw new CatalogoException("El porcentaje debe estar entre 0 y 100."); }
    private async Task EnsureAlicuotaName(int company, string name, int? except) { if (await _context.Alicuotas.AnyAsync(a => a.IdEmpresa == company && a.Id != except && a.Nombre.ToLower() == name.Trim().ToLower())) throw new CatalogoException("Ya existe una alícuota con ese nombre.", 409); }
}
