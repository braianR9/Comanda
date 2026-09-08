using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    [Table("usuarios")]
    public class Usuario
    {
        [Column("id_usuario")]
        public int Id { get; set; }

        [Column("id_empresa")]
        public int IdEmpresa { get; set; }

        [Column("id_sucursal")]
        public int IdSucursal { get; set; }

        [Column("id_rol")]
        public int IdRol { get; set; }

        [Column("nombre")]
        public string Nombre { get; set; } = string.Empty;

        [Column("apellido")]
        public string Apellido { get; set; } = string.Empty;

        [Column("email")]
        public string Email { get; set; } = string.Empty;

        [Column("password_hash")]
        public string PasswordHash { get; set; } = string.Empty;

        [Column("activo")]
        public bool Activo { get; set; }

        public Empresa Empresa { get; set; } = null!;
        public Sucursal Sucursal { get; set; } = null!;
        public Rol Rol { get; set; } = null!;
    }

    public class LoginRequestDto
    {
        public string Email { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

    public class LoginResponseDto
    {
        public string Token { get; set; } = string.Empty;
        public int Id { get; set; }
        public string Nombre { get; set; } = string.Empty;
        public string Apellido { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public int IdRol { get; set; }
        public int IdEmpresa { get; set; }
        public int IdSucursal { get; set; }
        public Empresa Empresa { get; set; } = null!;
        public Sucursal Sucursal { get; set; } = null!;
        public Rol Rol { get; set; } = null!;
    }
}
