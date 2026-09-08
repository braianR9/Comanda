using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    [Table("empresas")]
    public class Empresa
    {
        [Column("id_empresa")]
        public int Id { get; set; }

        [Column("nombre")]
        public string Nombre { get; set; } = string.Empty;

        [Column("cuit")]
        public string? Cuit { get; set; }

        [Column("email")]
        public string? Email { get; set; }

        [Column("telefono")]
        public string? Telefono { get; set; }

        [Column("imagen_url")]
        public string? ImagenUrl { get; set; }

        [Column("activa")]
        public bool Activa { get; set; }
    }
}
