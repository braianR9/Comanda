using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class UsuarioService(AppDbContext db)
{
    public async Task<List<RolDto>> ListRoles() =>
        await db.Roles.AsNoTracking().OrderBy(r => r.Nombre)
            .Select(r => new RolDto { Id = r.Id, Nombre = r.Nombre }).ToListAsync();

    public async Task<List<UsuarioDto>> List(int company, string? search, bool includeInactive)
    {
        var query = db.Usuarios.AsNoTracking()
            .Include(u => u.Rol)
            .Include(u => u.SectorAsignado)
            .Include(u => u.MesasExcluidas)
            .Where(u => u.IdEmpresa == company && (includeInactive || u.Activo));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            query = query.Where(u =>
                EF.Functions.ILike(u.Nombre, $"%{s}%") ||
                EF.Functions.ILike(u.Apellido, $"%{s}%") ||
                EF.Functions.ILike(u.Email, $"%{s}%"));
        }
        return await query.OrderBy(u => u.Nombre).Select(u => Dto(u)).ToListAsync();
    }

    public async Task<UsuarioDto?> Get(int company, int id) =>
        await db.Usuarios.AsNoTracking().Include(u => u.Rol)
            .Include(u => u.SectorAsignado).Include(u => u.MesasExcluidas)
            .Where(u => u.IdEmpresa == company && u.Id == id)
            .Select(u => Dto(u)).SingleOrDefaultAsync();

    public async Task<UsuarioDto> Create(int company, int branch, UsuarioRequest r)
    {
        Validate(r, requirePassword: true);
        await ValidateRol(company, r.IdRol);
        await ValidateEmailUnique(r.Email, null);
        var (sectorId, excludedIds) = await NormalizeAssignment(company, r);
        var entity = new Usuario
        {
            IdEmpresa = company,
            IdSucursal = branch,
            Activo = true,
        };
        Apply(entity, r);
        entity.IdSectorAsignado = sectorId;
        entity.MesasExcluidas = excludedIds.Select(id => new UsuarioMesaExcluida { IdMesa = id }).ToList();
        entity.PasswordHash = BCrypt.Net.BCrypt.HashPassword(r.Password!.Trim());
        db.Usuarios.Add(entity);
        await db.SaveChangesAsync();
        return await Reload(company, entity.Id);
    }

    public async Task<UsuarioDto> Update(int company, int id, UsuarioRequest r)
    {
        Validate(r, requirePassword: false);
        await ValidateRol(company, r.IdRol);
        var entity = await Entity(company, id);
        await ValidateEmailUnique(r.Email, id);
        if (entity.Rol?.Nombre == "ADMIN" && (!r.Activo || await IsOtherRol(r.IdRol)))
            await EnsureNotLastActiveAdmin(company, id);
        var (sectorId, excludedIds) = await NormalizeAssignment(company, r);
        Apply(entity, r);
        entity.IdSectorAsignado = sectorId;
        entity.MesasExcluidas.Clear();
        entity.MesasExcluidas.AddRange(excludedIds.Select(mesaId => new UsuarioMesaExcluida { IdUsuario = id, IdMesa = mesaId }));
        if (!string.IsNullOrWhiteSpace(r.Password))
            entity.PasswordHash = BCrypt.Net.BCrypt.HashPassword(r.Password.Trim());
        await db.SaveChangesAsync();
        return await Reload(company, entity.Id);
    }

    public async Task<UsuarioDto> SetActive(int company, int id, bool active, int currentUserId)
    {
        var entity = await Entity(company, id);
        if (!active)
        {
            if (entity.Id == currentUserId)
                throw new SaleException("No podés desactivar tu propio usuario.", 409);
            await EnsureNotLastActiveAdmin(company, id);
        }
        entity.Activo = active;
        await db.SaveChangesAsync();
        return await Reload(company, entity.Id);
    }

    private async Task<bool> IsOtherRol(int newIdRol)
    {
        var rol = await db.Roles.AsNoTracking().SingleOrDefaultAsync(r => r.Id == newIdRol);
        return rol?.Nombre != "ADMIN";
    }

    private async Task EnsureNotLastActiveAdmin(int company, int excludeId)
    {
        var otherActiveAdmins = await db.Usuarios.AsNoTracking()
            .Include(u => u.Rol)
            .Where(u => u.IdEmpresa == company && u.Activo && u.Id != excludeId && u.Rol.Nombre == "ADMIN")
            .AnyAsync();
        var current = await db.Usuarios.AsNoTracking().Include(u => u.Rol)
            .SingleOrDefaultAsync(u => u.Id == excludeId);
        if (current?.Rol.Nombre == "ADMIN" && !otherActiveAdmins)
            throw new SaleException("Debe quedar al menos un administrador activo.", 409);
    }

    private async Task<Usuario> Entity(int company, int id) =>
        await db.Usuarios.Include(u => u.Rol).Include(u => u.MesasExcluidas)
            .SingleOrDefaultAsync(u => u.IdEmpresa == company && u.Id == id)
        ?? throw new SaleException("Usuario no encontrado.", 404);

    private async Task<UsuarioDto> Reload(int company, int id) =>
        await Get(company, id) ?? throw new SaleException("Usuario no encontrado.", 404);

    private async Task ValidateRol(int company, int idRol)
    {
        if (!await db.Roles.AsNoTracking().AnyAsync(r => r.Id == idRol))
            throw new SaleException("El rol seleccionado no es válido.", 400);
    }

    private async Task ValidateEmailUnique(string email, int? excludeId)
    {
        // El login busca por email a nivel global, así que debe ser único en todo el sistema.
        var normalized = email.Trim().ToLowerInvariant();
        if (await db.Usuarios.AsNoTracking().AnyAsync(u => u.Id != excludeId && u.Email.ToLower() == normalized))
            throw new SaleException("Ya existe un usuario con ese email.", 409);
    }

    /// El sector asignado y las mesas excluidas solo aplican a empleados; para
    /// otros roles, o si no se eligió sector, se descartan las exclusiones.
    private async Task<(int? SectorId, List<int> ExcludedIds)> NormalizeAssignment(int company, UsuarioRequest r)
    {
        var rol = await db.Roles.AsNoTracking().SingleOrDefaultAsync(x => x.Id == r.IdRol);
        if (rol?.Nombre != "EMPLEADO" || r.IdSectorAsignado == null)
            return (null, []);

        var sectorId = r.IdSectorAsignado.Value;
        if (!await db.Sectors.AsNoTracking().AnyAsync(s => s.Id == sectorId && s.IdEmpresa == company))
            throw new SaleException("El sector asignado no es válido.", 400);

        var excludedIds = r.MesasExcluidasIds.Distinct().ToList();
        if (excludedIds.Count > 0)
        {
            var validCount = await db.Tables.AsNoTracking()
                .CountAsync(t => t.IdEmpresa == company && t.SectorId == sectorId && excludedIds.Contains(t.Id));
            if (validCount != excludedIds.Count)
                throw new SaleException("Alguna de las mesas excluidas no pertenece al sector asignado.", 400);
        }
        return (sectorId, excludedIds);
    }

    private static void Validate(UsuarioRequest r, bool requirePassword)
    {
        if (string.IsNullOrWhiteSpace(r.Nombre)) throw new SaleException("El nombre es obligatorio.");
        if (string.IsNullOrWhiteSpace(r.Apellido)) throw new SaleException("El apellido es obligatorio.");
        if (string.IsNullOrWhiteSpace(r.Email) || !r.Email.Contains('@'))
            throw new SaleException("El email no es válido.");
        if (requirePassword && string.IsNullOrWhiteSpace(r.Password))
            throw new SaleException("La contraseña es obligatoria.");
        if (!string.IsNullOrWhiteSpace(r.Password) && r.Password.Trim().Length < 6)
            throw new SaleException("La contraseña debe tener al menos 6 caracteres.");
    }

    private static void Apply(Usuario entity, UsuarioRequest r)
    {
        entity.Nombre = r.Nombre.Trim();
        entity.Apellido = r.Apellido.Trim();
        entity.Email = r.Email.Trim().ToLowerInvariant();
        entity.IdRol = r.IdRol;
        entity.Activo = r.Activo;
    }

    private static UsuarioDto Dto(Usuario u) => new()
    {
        Id = u.Id,
        Nombre = u.Nombre,
        Apellido = u.Apellido,
        Email = u.Email,
        IdRol = u.IdRol,
        RolNombre = u.Rol?.Nombre ?? string.Empty,
        IdSucursal = u.IdSucursal,
        SucursalNombre = u.Sucursal?.Nombre ?? string.Empty,
        Activo = u.Activo,
        IdSectorAsignado = u.IdSectorAsignado,
        SectorAsignadoNombre = u.SectorAsignado?.Nombre,
        MesasExcluidasIds = u.MesasExcluidas.Select(m => m.IdMesa).ToList(),
    };
}
