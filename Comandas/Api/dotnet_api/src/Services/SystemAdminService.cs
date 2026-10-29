using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class SystemAdminService(AppDbContext db, UsuarioService users)
{
    public async Task<Empresa> SaveCompany(int? id, SystemCompanyRequest r)
    {
        if (string.IsNullOrWhiteSpace(r.Nombre)) throw new SaleException("Indicá el nombre de la empresa.");
        if (!string.IsNullOrWhiteSpace(r.Email) && !new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(r.Email.Trim()))
            throw new SaleException("El correo de contacto no es válido.");
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var entity = id.HasValue ? await db.Empresas.SingleOrDefaultAsync(e => e.Id == id)
            ?? throw new SaleException("Empresa no encontrada.", 404) : new Empresa();
        var before = new { entity.Nombre, entity.Cuit, entity.Email, entity.Telefono, entity.Activa };
        entity.Nombre = r.Nombre.Trim(); entity.Cuit = Clean(r.Cuit); entity.Email = Clean(r.Email);
        entity.Telefono = Clean(r.Telefono); entity.Activa = r.Activa;
        if (!id.HasValue) db.Empresas.Add(entity);
        await db.SaveChangesAsync();
        Audit(id.HasValue ? "Empresa modificada" : "Empresa creada", entity.Id, null,
            new { before, after = new { entity.Nombre, entity.Cuit, entity.Email, entity.Telefono, entity.Activa } });
        await db.SaveChangesAsync(); if (tx != null) await tx.CommitAsync(); return entity;
    }

    public async Task<Sucursal> SaveBranch(int company, int? id, SystemBranchRequest r)
    {
        if (string.IsNullOrWhiteSpace(r.Nombre)) throw new SaleException("Indicá el nombre de la sucursal.");
        if (!await db.Empresas.AnyAsync(x => x.Id == company)) throw new SaleException("Empresa no encontrada.", 404);
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var entity = id.HasValue ? await db.Sucursales.SingleOrDefaultAsync(s => s.Id == id && s.IdEmpresa == company)
            ?? throw new SaleException("Sucursal no encontrada en esta empresa.", 404) : new Sucursal { IdEmpresa = company };
        if (await db.Sucursales.AnyAsync(s => s.IdEmpresa == company && s.Id != (id ?? 0) && s.Nombre.ToLower() == r.Nombre.Trim().ToLower()))
            throw new SaleException("Ya existe una sucursal con ese nombre.", 409);
        var before = new { entity.Nombre, entity.Direccion, entity.Telefono, entity.Activa };
        entity.Nombre = r.Nombre.Trim(); entity.Direccion = Clean(r.Direccion); entity.Telefono = Clean(r.Telefono); entity.Activa = r.Activa;
        if (!id.HasValue) db.Sucursales.Add(entity);
        await db.SaveChangesAsync();
        Audit(id.HasValue ? "Sucursal modificada" : "Sucursal creada", company, entity.Id,
            new { before, after = new { entity.Nombre, entity.Direccion, entity.Telefono, entity.Activa } });
        await db.SaveChangesAsync(); if (tx != null) await tx.CommitAsync(); return entity;
    }

    public async Task<UsuarioDto> SaveUser(int company, int? id, SystemUserRequest r)
    {
        if (!await db.Sucursales.AnyAsync(s => s.Id == r.IdSucursal && s.IdEmpresa == company))
            throw new SaleException("La sucursal no pertenece a la empresa seleccionada.");
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var before = id.HasValue ? await users.Get(company, id.Value) ?? throw new SaleException("Usuario no encontrado.", 404) : null;
        var result = id.HasValue ? await users.Update(company, id.Value, r, enforceLastAdmin: false) : await users.Create(company, r.IdSucursal, r);
        var entity = await db.Usuarios.SingleAsync(u => u.Id == result.Id && u.IdEmpresa == company);
        if (entity.IdSucursal != r.IdSucursal)
        {
            entity.IdSucursal = r.IdSucursal;
            entity.IdSectorAsignado = null;
            var exclusions = await db.UsuarioMesasExcluidas.Where(m => m.IdUsuario == entity.Id).ToListAsync();
            db.UsuarioMesasExcluidas.RemoveRange(exclusions);
        }
        Audit(id.HasValue ? "Usuario modificado" : "Usuario creado", company, r.IdSucursal,
            new { id = entity.Id, before = before == null ? null : new { before.Nombre, before.Apellido, before.Email, before.IdRol, before.IdSucursal, before.Activo },
                after = new { entity.Nombre, entity.Apellido, entity.Email, entity.IdRol, entity.IdSucursal, entity.Activo },
                passwordChanged = !string.IsNullOrWhiteSpace(r.Password) });
        await db.SaveChangesAsync(); if (tx != null) await tx.CommitAsync();
        return (await users.Get(company, result.Id))!;
    }

    public void Audit(string message, int? company, int? branch, object? detail = null) => db.SystemEvents.Add(new SystemEvent
    {
        Type = "Audit", Level = "Information", Source = "Sistemas", Message = message,
        CompanyId = company, BranchId = branch,
        Detail = detail == null ? null : System.Text.Json.JsonSerializer.Serialize(detail)
    });
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
