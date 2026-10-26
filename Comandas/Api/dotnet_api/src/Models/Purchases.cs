using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
namespace BarIceCreamShop.Api.Models;

[Table("proveedores")]
public class Supplier
{
    [Column("id_proveedor")] public int Id { get; set; }
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("nombre")] public string Name { get; set; } = "";
    [Column("cuit")] public string? Cuit { get; set; }
    [Column("condicion_iva")] public string TaxCondition { get; set; } = "";
    [Column("contacto")] public string Contact { get; set; } = "";
    [Column("telefono")] public string Phone { get; set; } = "";
    [Column("email")] public string Email { get; set; } = "";
    [Column("direccion")] public string Address { get; set; } = "";
    [Column("observaciones")] public string Notes { get; set; } = "";
    [Column("activo")] public bool Active { get; set; } = true;
    [Column("version")] public int Version { get; set; } = 1;
}
[Table("proveedor_productos")]
public class SupplierProduct
{
    [Column("id_proveedor")] public int SupplierId { get; set; }
    [Column("id_producto")] public int ProductId { get; set; }
    [Column("codigo_proveedor")] public string Code { get; set; } = "";
}
[Table("compras")]
public class Purchase
{
    [Column("id_compra")] public int Id { get; set; }
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("id_sucursal")] public int BranchId { get; set; }
    [Column("id_proveedor")] public int SupplierId { get; set; }
    [Column("proveedor_nombre")] public string SupplierName { get; set; } = "";
    [Column("tipo_comprobante")] public string DocumentType { get; set; } = "Remito";
    [Column("letra")] public string Letter { get; set; } = "";
    [Column("punto_venta")] public int PointOfSale { get; set; }
    [Column("numero")] public string Number { get; set; } = "";
    [Column("fecha_comprobante")] public DateOnly DocumentDate { get; set; }
    [Column("total_comprobante")] public decimal? DocumentTotal { get; set; }
    [Column("observaciones")] public string Notes { get; set; } = "";
    [Column("estado")] public string Status { get; set; } = "Borrador";
    [Column("version")] public int Version { get; set; } = 1;
    [Column("id_usuario_carga")] public int CreatedBy { get; set; }
    [Column("usuario_carga")] public string CreatedByName { get; set; } = "";
    [Column("fecha_carga")] public DateTime CreatedAt { get; set; }
    [Column("id_usuario_control")] public int? ControlledBy { get; set; }
    [Column("usuario_control")] public string? ControlledByName { get; set; }
    [Column("fecha_control")] public DateTime? ControlledAt { get; set; }
    [Column("clave_solicitud")] public string RequestKey { get; set; } = "";
    public List<PurchaseItem> Items { get; set; } = [];
}
[Table("compra_items")]
public class PurchaseItem
{
    [Column("id_compra")] public int PurchaseId { get; set; }
    [Column("id_producto")] public int ProductId { get; set; }
    [Column("producto_nombre")] public string ProductName { get; set; } = "";
    [Column("cantidad")] public decimal Quantity { get; set; }
    [Column("costo_unitario")] public decimal UnitCost { get; set; }
}
[Table("compra_historial")]
public class PurchaseAudit
{
    [Column("id_evento")] public long Id { get; set; }
    [Column("id_compra")] public int PurchaseId { get; set; }
    [Column("id_usuario")] public int UserId { get; set; }
    [Column("usuario")] public string UserName { get; set; } = "";
    [Column("fecha")] public DateTime Date { get; set; }
    [Column("accion")] public string Action { get; set; } = "";
    [Column("motivo")] public string Reason { get; set; } = "";
    [Column("datos", TypeName = "jsonb")] public string Snapshot { get; set; } = "{}";
}
public class SupplierRequest
{
    [Required, MaxLength(200)] public string Name { get; set; } = "";
    [MaxLength(20)] public string? Cuit { get; set; }
    [MaxLength(80)] public string TaxCondition { get; set; } = "";
    [MaxLength(150)] public string Contact { get; set; } = "";
    [MaxLength(60)] public string Phone { get; set; } = "";
    [MaxLength(200)] public string Email { get; set; } = "";
    [MaxLength(300)] public string Address { get; set; } = "";
    [MaxLength(1000)] public string Notes { get; set; } = "";
    public bool Active { get; set; } = true;
    public int Version { get; set; }
    [Required, MaxLength(500)] public List<SupplierProductRequest> Products { get; set; } = [];
}
public record SupplierProductRequest([param: Range(1,int.MaxValue)] int ProductId, [param: MaxLength(80)] string Code = "");
public class PurchaseRequest
{
    [Range(1,int.MaxValue)] public int SupplierId { get; set; }
    [Required, MaxLength(20)] public string DocumentType { get; set; } = "Remito";
    [MaxLength(1)] public string Letter { get; set; } = "";
    [Range(0,99999)] public int PointOfSale { get; set; }
    [Required, MaxLength(30)] public string Number { get; set; } = "";
    public DateOnly DocumentDate { get; set; }
    [Range(typeof(decimal),"0","9999999999999.99", ParseLimitsInInvariantCulture=true)] public decimal? DocumentTotal { get; set; }
    [MaxLength(1000)] public string Notes { get; set; } = "";
    [Required, MinLength(1), MaxLength(200)] public List<PurchaseItemRequest> Items { get; set; } = [];
    public int Version { get; set; }
    [Required, MaxLength(64)] public string RequestKey { get; set; } = "";
}
public record PurchaseItemRequest([param: Range(1,int.MaxValue)] int ProductId,
    [param: Range(typeof(decimal),"0.001","999999999999.999", ParseLimitsInInvariantCulture=true)] decimal Quantity,
    [param: Range(typeof(decimal),"0","9999999999999.99", ParseLimitsInInvariantCulture=true)] decimal UnitCost);
public record PurchaseActionRequest(int Version, [param: MaxLength(1000)] string Reason = "");
