using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using BarIceCreamShop.Api.Data;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace BarIceCreamShop.Api.Security;

// Esta identidad no es un rol de usuarios: solamente se configura en el servidor.
public static class SystemsOwner
{
    public const string Policy = "SystemsOwner";
    public const string Subject = "systems-owner";
    public static string UserStamp(string passwordHash) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(passwordHash)));
    public static string Stamp(IConfiguration config) => Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes((config["SystemsOwner:Email"] ?? "").ToLowerInvariant() + "|" + config["SystemsOwner:PasswordHash"])));
    public static bool IsOwner(ClaimsPrincipal user, IConfiguration config) =>
        user.Identity?.IsAuthenticated == true &&
        user.FindFirstValue(ClaimTypes.NameIdentifier) == Subject &&
        user.FindFirstValue("scope") == "systems" &&
        !string.IsNullOrWhiteSpace(config["SystemsOwner:PasswordHash"]) &&
        string.Equals(user.FindFirstValue(ClaimTypes.Email), config["SystemsOwner:Email"], StringComparison.OrdinalIgnoreCase) &&
        user.FindFirstValue("owner_stamp") == Stamp(config);

    public static string CreateToken(IConfiguration config)
    {
        var jwt = config.GetSection("Jwt");
        var token = new JwtSecurityToken(jwt["Issuer"], jwt["Audience"], [
            new Claim(ClaimTypes.NameIdentifier, Subject),
            new Claim(ClaimTypes.Email, config["SystemsOwner:Email"]!),
            new Claim("scope", "systems"), new Claim("owner_stamp", Stamp(config)),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        ], expires: DateTime.UtcNow.AddMinutes(30), signingCredentials: new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!)), SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public static async Task ValidateSession(TokenValidatedContext context)
    {
        var config = context.HttpContext.RequestServices.GetRequiredService<IConfiguration>();
        var user = context.Principal!;
        if (user.FindFirstValue("scope") == "systems")
        {
            if (!IsOwner(user, config) || !context.Request.Path.StartsWithSegments("/api/system"))
                context.Fail("Sesión de sistemas inválida para este acceso.");
            return;
        }
        var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
        var role = user.FindFirstValue("rol_nombre");
        var stamp = user.FindFirstValue("session_stamp");
        if (!int.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ||
            !int.TryParse(user.FindFirstValue("id_empresa"), out var company) ||
            !int.TryParse(user.FindFirstValue("id_sucursal"), out var branch))
        {
            context.Fail("Sesión inválida.");
            return;
        }
        var hash = await db.Usuarios.AsNoTracking().Where(u => u.Id == id && u.IdEmpresa == company &&
                u.IdSucursal == branch && u.Activo && u.Empresa.Activa && u.Sucursal.Activa &&
                u.Sucursal.IdEmpresa == company &&
                (u.Rol.Nombre == role || (u.Rol.Nombre == "ENCARGADO" && role == "CAJA")))
            .Select(u => u.PasswordHash).SingleOrDefaultAsync(context.HttpContext.RequestAborted);
        if (hash == null || stamp != UserStamp(hash))
            context.Fail("El acceso está deshabilitado o cambió. Iniciá sesión nuevamente.");
    }
}
