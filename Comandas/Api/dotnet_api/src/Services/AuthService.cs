using Microsoft.EntityFrameworkCore;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace BarIceCreamShop.Api.Services
{
    public class AuthService
    {
        private readonly AppDbContext _context;
        private readonly IConfiguration _configuration;

        public AuthService(AppDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        public async Task<LoginResponseDto?> LoginAsync(LoginRequestDto dto)
        {
            // Busca el usuario activo por email
            var usuario = await _context.Usuarios
                .AsNoTracking()
                .Include(u => u.Empresa)
                .Include(u => u.Sucursal)
                .Include(u => u.Rol)
                .Include(u => u.MesasExcluidas)
                .FirstOrDefaultAsync(u => u.Email == dto.Email && u.Activo);

            if (usuario == null)
                return null;

            // Contraseñas nuevas se guardan con BCrypt; las cuentas antiguas (texto plano)
            // se siguen aceptando para no romper sesiones existentes.
            var passwordValid = usuario.PasswordHash.StartsWith("$2")
                ? BCrypt.Net.BCrypt.Verify(dto.Password, usuario.PasswordHash)
                : usuario.PasswordHash == dto.Password;
            if (!passwordValid)
                return null;

            return new LoginResponseDto
            {
                Token      = CreateToken(usuario),
                Id         = usuario.Id,
                Nombre     = usuario.Nombre,
                Apellido   = usuario.Apellido,
                Email      = usuario.Email,
                IdRol      = usuario.IdRol,
                IdEmpresa  = usuario.IdEmpresa,
                IdSucursal = usuario.IdSucursal,
                Empresa    = usuario.Empresa,
                Sucursal   = usuario.Sucursal,
                Rol        = usuario.Rol,
                IdSectorAsignado   = usuario.IdSectorAsignado,
                MesasExcluidasIds  = usuario.MesasExcluidas.Select(m => m.IdMesa).ToList(),
            };
        }

        private string CreateToken(Usuario usuario)
        {
            var jwt = _configuration.GetSection("Jwt");
            var claims = new[]
            {
                new Claim(ClaimTypes.NameIdentifier, usuario.Id.ToString()),
                new Claim(ClaimTypes.Email, usuario.Email),
                new Claim(ClaimTypes.Role, usuario.IdRol.ToString()),
                new Claim("rol_nombre", usuario.Rol.Nombre),
                new Claim("id_empresa", usuario.IdEmpresa.ToString()),
                new Claim("id_sucursal", usuario.IdSucursal.ToString())
            };
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!));
            var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
            var token = new JwtSecurityToken(jwt["Issuer"], jwt["Audience"], claims,
                expires: DateTime.UtcNow.AddMinutes(jwt.GetValue<int>("DurationInMinutes")),
                signingCredentials: credentials);
            return new JwtSecurityTokenHandler().WriteToken(token);
        }
    }
}
