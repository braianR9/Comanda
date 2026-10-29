using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize(Policy = SystemsOwner.Policy), Route("api/system")]
public sealed class SystemAdminController(AppDbContext db, SystemAdminService service, UsuarioService users,
    IConfiguration config) : ControllerBase
{
    [HttpPost("client-error"), EnableRateLimiting("client-errors")]
    public object ClientError(ClientErrorRequest request, [FromServices] SystemEventSink sink)
    {
        sink.Error("Flutter · Sistemas", request.Message + "\n" + request.Library + "\n" + request.Stack);
        return ApiResponse<object>.Ok(new { reference = HttpContext.TraceIdentifier });
    }
    [AllowAnonymous, EnableRateLimiting("systems-login"), HttpPost("login")]
    public async Task<ActionResult<ApiResponse<object>>> Login(LoginRequestDto request)
    {
        var hash = config["SystemsOwner:PasswordHash"];
        var matches = !string.IsNullOrWhiteSpace(hash) &&
            string.Equals(request.Email.Trim(), config["SystemsOwner:Email"], StringComparison.OrdinalIgnoreCase);
        // Verificar también en intentos con otro correo para no revelar la identidad configurada por tiempos.
        var valid = false;
        if (!string.IsNullOrEmpty(hash) && System.Text.Encoding.UTF8.GetByteCount(request.Password) <= 72)
        {
            try { valid = BCrypt.Net.BCrypt.Verify(request.Password, hash); }
            catch (BCrypt.Net.SaltParseException) { }
        }
        if (!matches || !valid)
            return Unauthorized(ApiResponse<object>.Fail("Credenciales de sistemas incorrectas.", 401));
        service.Audit("Ingreso del propietario al panel de sistemas", null, null);
        await db.SaveChangesAsync();
        return Ok(ApiResponse<object>.Ok(new { token = SystemsOwner.CreateToken(config), email = config["SystemsOwner:Email"], expiresInMinutes = 30 }));
    }

    [HttpGet("session")]
    public object Session() => ApiResponse<object>.Ok(new { email = config["SystemsOwner:Email"] });

    [HttpPut("password")]
    public async Task<object> ChangePassword(SystemPasswordRequest request)
    {
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SystemsOwner__PasswordHash")))
            throw new SaleException("Esta contraseña se administra mediante variables de entorno del servidor.", 409);
        if (System.Text.Encoding.UTF8.GetByteCount(request.CurrentPassword) > 72 ||
            !BCrypt.Net.BCrypt.Verify(request.CurrentPassword, config["SystemsOwner:PasswordHash"]))
            throw new SaleException("La contraseña actual es incorrecta.", 401);
        if (System.Text.Encoding.UTF8.GetByteCount(request.NewPassword) > 72)
            throw new SaleException("La contraseña nueva no debe superar 72 bytes.");
        service.Audit("Contraseña de sistemas modificada; sesiones anteriores revocadas", null, null);
        await db.SaveChangesAsync();
        SystemsSetup.SaveOwner(config["SystemsOwner:Email"]!, request.NewPassword);
        if (config is IConfigurationRoot root) root.Reload();
        return ApiResponse<object>.Ok(new { token = SystemsOwner.CreateToken(config) });
    }

    [HttpGet("companies")]
    public async Task<object> Companies(string? search, int page = 1, int pageSize = 30)
    {
        Bounds(ref page, ref pageSize);
        var query = db.Empresas.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => EF.Functions.ILike(x.Nombre, $"%{search.Trim()}%"));
        var total = await query.CountAsync();
        var items = await query.OrderBy(x => x.Nombre).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(e => new { e.Id, e.Nombre, e.Cuit, e.Email, e.Telefono, e.Activa,
                branches = db.Sucursales.Count(s => s.IdEmpresa == e.Id), users = db.Usuarios.Count(u => u.IdEmpresa == e.Id) }).ToListAsync();
        return ApiResponse<object>.Ok(new { items, total, page, pageSize });
    }
    [HttpPost("companies")] public async Task<object> CreateCompany(SystemCompanyRequest request) => ApiResponse<Empresa>.Ok(await service.SaveCompany(null, request));
    [HttpPut("companies/{company:int}")] public async Task<object> Company(int company, SystemCompanyRequest request) => ApiResponse<Empresa>.Ok(await service.SaveCompany(company, request));

    [HttpGet("companies/{company:int}/branches")]
    public async Task<object> Branches(int company) => ApiResponse<object>.Ok(await db.Sucursales.AsNoTracking()
        .Where(s => s.IdEmpresa == company).OrderBy(s => s.Nombre).ToListAsync());
    [HttpPost("companies/{company:int}/branches")] public async Task<object> CreateBranch(int company, SystemBranchRequest request) => ApiResponse<Sucursal>.Ok(await service.SaveBranch(company, null, request));
    [HttpPut("companies/{company:int}/branches/{branch:int}")] public async Task<object> Branch(int company, int branch, SystemBranchRequest request) => ApiResponse<Sucursal>.Ok(await service.SaveBranch(company, branch, request));

    [HttpGet("companies/{company:int}/users")]
    public async Task<object> Users(int company, string? search, int page = 1, int pageSize = 30)
    {
        Bounds(ref page, ref pageSize);
        var query = db.Usuarios.AsNoTracking().Where(u => u.IdEmpresa == company);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(u => EF.Functions.ILike(u.Nombre + " " + u.Apellido + " " + u.Email, $"%{search.Trim()}%"));
        var total = await query.CountAsync();
        var items = await query.OrderBy(u => u.Nombre).ThenBy(u => u.Id).Skip((page - 1) * pageSize).Take(pageSize).Select(u => new {
            u.Id, u.Nombre, u.Apellido, u.Email, u.IdRol, rolNombre = u.Rol.Nombre == "ENCARGADO" ? "CAJA" : u.Rol.Nombre,
            u.IdSucursal, sucursalNombre = u.Sucursal.Nombre, u.Activo, u.IdSectorAsignado,
            mesasExcluidasIds = u.MesasExcluidas.Select(m => m.IdMesa).ToList()
        }).ToListAsync();
        return ApiResponse<object>.Ok(new { items, total, page, pageSize });
    }
    [HttpGet("roles")] public async Task<object> Roles() => ApiResponse<object>.Ok(await users.ListRoles());
    [HttpPost("companies/{company:int}/users")] public async Task<object> CreateUser(int company, SystemUserRequest request) => ApiResponse<UsuarioDto>.Ok(await service.SaveUser(company, null, request));
    [HttpPut("companies/{company:int}/users/{user:int}")] public async Task<object> UserAccount(int company, int user, SystemUserRequest request) => ApiResponse<UsuarioDto>.Ok(await service.SaveUser(company, user, request));

    [HttpGet("transactions")]
    public async Task<object> Transactions(DateTimeOffset from, DateTimeOffset to, int? company, int? branch,
        string? status, string kind = "sales", int page = 1, int pageSize = 30, int utcOffsetMinutes = -180)
    {
        Bounds(ref page, ref pageSize);
        var (start, end) = Dates(from, to);
        if (utcOffsetMinutes is < -840 or > 840) throw new SaleException("Zona horaria inválida.");
        var sales = db.Orders.AsNoTracking().Where(s => (!company.HasValue || s.IdEmpresa == company) &&
            (!branch.HasValue || s.IdSucursal == branch));
        if (!string.IsNullOrWhiteSpace(status)) sales = sales.Where(s => s.Estado == status);
        if (kind == "payments")
        {
            var query = from s in sales from p in s.Payments
                where p.Fecha >= start && p.Fecha < end
                join e in db.Empresas on s.IdEmpresa equals e.Id
                join b in db.Sucursales on s.IdSucursal equals b.Id
                select new { p.Id, saleId = s.Id, s.Numero, company = e.Nombre, branch = b.Nombre,
                    date = p.Fecha, p.Amount, p.PaymentTypeName, status = s.Estado, isRefund = false };
            var refunds = from s in sales join r in db.SaleRefunds on s.Id equals r.OrderId
                join v in db.SaleVoids on s.Id equals v.OrderId
                join e in db.Empresas on s.IdEmpresa equals e.Id
                join b in db.Sucursales on s.IdSucursal equals b.Id
                where v.Date >= start && v.Date < end
                select new { r.Id, saleId = s.Id, s.Numero, company = e.Nombre, branch = b.Nombre,
                    date = v.Date, Amount = -r.Amount, r.PaymentTypeName, status = s.Estado, isRefund = true };
            query = query.Concat(refunds);
            var total = await query.CountAsync();
            var amount = await query.SumAsync(p => (decimal?)p.Amount) ?? 0;
            var daily = await query.GroupBy(p => p.date.AddMinutes(utcOffsetMinutes).Date).Select(g => new { date = g.Key, count = g.Count(), amount = g.Sum(p => p.Amount) }).OrderBy(g => g.date).ToListAsync();
            return ApiResponse<object>.Ok(new { items = await query.OrderByDescending(p => p.date).ThenByDescending(p => p.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(), total, page, pageSize, amount, daily });
        }
        if (kind != "sales") throw new SaleException("Tipo de transacción inválido.");
        var filtered = sales.Where(s => (s.FechaCierre ?? s.FechaApertura) >= start && (s.FechaCierre ?? s.FechaApertura) < end);
        var count = await filtered.CountAsync();
        var billed = await filtered.Where(s => s.Estado == "Finalizada").SumAsync(s => (decimal?)s.Total) ?? 0;
        var days = await filtered.Where(s => s.Estado == "Finalizada").GroupBy(s => (s.FechaCierre ?? s.FechaApertura).AddMinutes(utcOffsetMinutes).Date)
            .Select(g => new { date = g.Key, count = g.Count(), amount = g.Sum(s => s.Total) }).OrderBy(g => g.date).ToListAsync();
        var rows = await (from s in filtered join e in db.Empresas on s.IdEmpresa equals e.Id
            join b in db.Sucursales on s.IdSucursal equals b.Id
            orderby (s.FechaCierre ?? s.FechaApertura) descending, s.Id descending
            select new { s.Id, s.Numero, company = e.Nombre, branch = b.Nombre, date = s.FechaCierre ?? s.FechaApertura,
                status = s.Estado, amount = s.Total,
                paid = (s.Payments.Sum(p => (decimal?)p.Amount) ?? 0) - (db.SaleRefunds.Where(r => r.OrderId == s.Id).Sum(r => (decimal?)r.Amount) ?? 0) })
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync();
        return ApiResponse<object>.Ok(new { items = rows, total = count, page, pageSize, amount = billed, daily = days });
    }

    [HttpGet("events")]
    public async Task<object> Events(DateTimeOffset from, DateTimeOffset to, string type = "Error", int? company = null,
        int? branch = null, bool? resolved = null, string? search = null, int page = 1, int pageSize = 30)
    {
        Bounds(ref page, ref pageSize); var (start, end) = Dates(from, to);
        if (type is not ("Error" or "Audit")) throw new SaleException("Tipo de evento inválido.");
        var query = db.SystemEvents.AsNoTracking().Where(e => e.Date >= start && e.Date < end && e.Type == type &&
            (!company.HasValue || e.CompanyId == company) && (!branch.HasValue || e.BranchId == branch) &&
            (!resolved.HasValue || e.Resolved == resolved));
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(e => EF.Functions.ILike(e.Message, $"%{search.Trim()}%") || EF.Functions.ILike(e.TraceId!, $"%{search.Trim()}%"));
        return ApiResponse<object>.Ok(new { items = await query.OrderByDescending(e => e.Date).ThenByDescending(e => e.Id)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(), total = await query.CountAsync(), page, pageSize });
    }
    [HttpGet("transactions/{id:int}")]
    public async Task<object> Transaction(int id)
    {
        var sale = await (from s in db.Orders.AsNoTracking()
            join e in db.Empresas on s.IdEmpresa equals e.Id
            join b in db.Sucursales on s.IdSucursal equals b.Id
            where s.Id == id
            select new { s.Id, s.Numero, s.Estado, s.FechaApertura, s.FechaCierre,
                s.Subtotal, s.ImporteDescuento, s.Total, company = e.Nombre, branch = b.Nombre,
                items = s.Items.Select(i => new { i.ProductName, i.Quantity, i.UnitPrice, i.Subtotal, i.Comment, i.Estado }).ToList(),
                payments = s.Payments.Select(p => new { p.PaymentTypeName, p.Amount, p.Fecha }).ToList(),
                annulment = db.SaleVoids.Where(v => v.OrderId == s.Id).Select(v => new { v.Date, v.Reason, v.Refunded, v.UserId }).FirstOrDefault()
            }).SingleOrDefaultAsync() ?? throw new SaleException("Venta no encontrada.", 404);
        return ApiResponse<object>.Ok(sale);
    }
    [HttpPut("events/{id:long}/resolution")]
    public async Task<object> Resolve(long id, SystemEventResolution request)
    {
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var item = await db.SystemEvents.SingleOrDefaultAsync(e => e.Id == id && e.Type == "Error") ?? throw new SaleException("Error no encontrado.", 404);
        item.Resolved = request.Resolved; item.Note = request.Note?.Trim();
        service.Audit(request.Resolved ? "Error marcado como resuelto" : "Error reabierto", item.CompanyId, item.BranchId, new { eventId = id, item.Note });
        await db.SaveChangesAsync(); if (tx != null) await tx.CommitAsync(); return ApiResponse<SystemEvent>.Ok(item);
    }
    private static void Bounds(ref int page, ref int size) { page = Math.Clamp(page, 1, 100000); size = Math.Clamp(size, 1, 100); }
    private static (DateTime Start, DateTime End) Dates(DateTimeOffset from, DateTimeOffset to)
    {
        if (from == default || to <= from || to - from > TimeSpan.FromDays(366))
            throw new SaleException("Elegí un período válido de hasta 366 días.");
        return (from.UtcDateTime, to.UtcDateTime);
    }
}
