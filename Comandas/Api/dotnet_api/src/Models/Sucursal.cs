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

        /// ID de la planilla de Google Sheets donde se vuelcan las ventas finalizadas; null = desactivado.
        [Column("google_sheet_id")]
        public string? GoogleSheetId { get; set; }

        /// Lista de precios que usa esta sucursal por defecto; null = usa la predeterminada de la empresa.
        [Column("id_lista_precio_predeterminada")]
        public int? IdListaPrecioPredeterminada { get; set; }
    }
}
