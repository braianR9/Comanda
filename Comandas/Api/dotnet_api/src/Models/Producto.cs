using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("productos")]
public class Producto
{
    [Column("id_producto")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("codigo")] public int Codigo { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("tipo_producto")] public string TipoProducto { get; set; } = "ProductoSimple";
    [Column("id_rubro")] public int IdRubro { get; set; }
    [Column("id_subrubro")] public int? IdSubRubro { get; set; }
    [Column("id_alicuota")] public int IdAlicuota { get; set; }
    [Column("costo_con_iva", TypeName = "decimal(18,2)")] public decimal CostoConIva { get; set; }
    [Column("precio_con_iva", TypeName = "decimal(18,2)")] public decimal PrecioConIva { get; set; }
    [Column("imagen_url")] public string? ImagenUrl { get; set; }
    [Column("activo")] public bool Activo { get; set; } = true;
    [Column("mostrar_delivery")] public bool MostrarDelivery { get; set; }
    [Column("mostrar_salon")] public bool MostrarSalon { get; set; }
    [Column("mostrar_carta_digital")] public bool MostrarCartaDigital { get; set; }
    [Column("solicitar_cantidad")] public bool SolicitarCantidad { get; set; }
    [Column("solicitar_precio_unitario")] public bool SolicitarPrecioUnitario { get; set; }
    [Column("solicitar_precio_y_calcular_cantidad")] public bool SolicitarPrecioYCalcularCantidad { get; set; }
    [Column("preparacion")] public string? Preparacion { get; set; }
    [Column("orden")] public int Orden { get; set; }
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }

    public Rubro Rubro { get; set; } = null!;
    public SubRubro? SubRubro { get; set; }
    public Alicuota Alicuota { get; set; } = null!;
}

[Table("rubros")]
public class Rubro
{
    [Column("id_rubro")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("tipo_observacion")] public string TipoObservacion { get; set; } = "SinObservaciones";
    [Column("imagen_url")] public string? ImagenUrl { get; set; }
    [Column("aplicar_productos")] public bool AplicarProductos { get; set; } = true;
    [Column("aplicar_delivery")] public bool AplicarDelivery { get; set; }
    [Column("aplicar_salon")] public bool AplicarSalon { get; set; }
    [Column("mostrar_carta_digital")] public bool MostrarCartaDigital { get; set; }
    [Column("activo")] public bool Activo { get; set; } = true;
}

[Table("subrubros")]
public class SubRubro
{
    [Column("id_subrubro")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_rubro")] public int IdRubro { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("tipo_observacion")] public string TipoObservacion { get; set; } = "SinObservaciones";
    [Column("imagen_url")] public string? ImagenUrl { get; set; }
    [Column("aplicar_productos")] public bool AplicarProductos { get; set; } = true;
    [Column("aplicar_ingredientes")] public bool AplicarIngredientes { get; set; }
    [Column("aplicar_delivery")] public bool AplicarDelivery { get; set; }
    [Column("aplicar_salon")] public bool AplicarSalon { get; set; }
    [Column("mostrar_carta_digital")] public bool MostrarCartaDigital { get; set; }
    [Column("activo")] public bool Activo { get; set; } = true;
}

[Table("alicuotas")]
public class Alicuota
{
    [Column("id_alicuota")] public int Id { get; set; }
    [Column("id_empresa")] public int? IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string Descripcion { get; set; } = string.Empty;
    [Column("porcentaje", TypeName = "decimal(5,2)")] public decimal Porcentaje { get; set; }
    [Column("activa")] public bool Activa { get; set; } = true;
}

[Table("producto_codigo_contadores")]
public class ProductoCodigoContador
{
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("ultimo_codigo")] public int UltimoCodigo { get; set; }
}

[Table("stock_productos")]
public class StockProducto
{
    [Column("id_stock_producto")] public int Id { get; set; }
    [Column("id_producto")] public int IdProducto { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("operacion_cantidad")] public string OperacionCantidad { get; set; } = "Entero";
    [Column("stock_actual", TypeName = "decimal(18,3)")] public decimal StockActual { get; set; }
    [Column("stock_minimo", TypeName = "decimal(18,3)")] public decimal StockMinimo { get; set; }
    [Column("stock_ideal", TypeName = "decimal(18,3)")] public decimal StockIdeal { get; set; }
    [Column("tiene_alarma_stock")] public bool TieneAlarmaStock { get; set; }
    [Column("tiene_alarma_stock_minimo")] public bool TieneAlarmaStockMinimo { get; set; }
    [Column("comprobar_stock_al_vender")] public bool ComprobarStockAlVender { get; set; }
    [Column("actualizar_sobre")] public string ActualizarSobre { get; set; } = "Producto";
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
    public Producto Producto { get; set; } = null!;
    public Sucursal Sucursal { get; set; } = null!;
}
