using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    [Table("sucursales")]
    public class Sucursal
    {
        [Column("id_sucursal")]
        public int Id { get; set; }

        [Column("id_empresa")]
        public int IdEmpresa { get; set; }

        [Column("nombre")]
        public string Nombre { get; set; } = string.Empty;

        [Column("direccion")]
        public string? Direccion { get; set; }

        [Column("telefono")]
        public string? Telefono { get; set; }

        [Column("activa")]
        public bool Activa { get; set; }
    }
}
