using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("listas_precios")]
public class ListaPrecio
{
    [Column("id_lista_precio")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("es_predeterminada")] public bool EsPredeterminada { get; set; }
    [Column("activa")] public bool Activa { get; set; } = true;
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}

[Table("producto_precios")]
public class ProductoPrecio
{
    [Column("id_producto")] public int IdProducto { get; set; }
    [Column("id_lista_precio")] public int IdListaPrecio { get; set; }
    [Column("precio", TypeName = "decimal(18,2)")] public decimal Precio { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}
