using System.ComponentModel.DataAnnotations.Schema;
namespace BarIceCreamShop.Api.Models;
[Table("precio_historial")]
public class PriceHistory
{
    [Column("id")] public long Id { get; set; }
    [Column("lote")] public Guid Lote { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_lista_precio")] public int IdListaPrecio { get; set; }
    [Column("lista_nombre")] public string ListaNombre { get; set; } = "";
    [Column("id_producto")] public int IdProducto { get; set; }
    [Column("producto_nombre")] public string ProductoNombre { get; set; } = "";
    [Column("precio_anterior")] public decimal? PrecioAnterior { get; set; }
    [Column("precio_nuevo")] public decimal? PrecioNuevo { get; set; }
    [Column("fecha")] public DateTime Fecha { get; set; }
    [Column("usuario")] public string Usuario { get; set; } = "";
    [Column("motivo")] public string Motivo { get; set; } = "";
    [Column("revertido_por")] public Guid? RevertidoPor { get; set; }
}
