using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("ventas")]
public class Order
{
    [Column("id_venta")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("numero")] public int Numero { get; set; }
    [Column("id_mesa")] public int TableId { get; set; }
    [Column("id_mozo")] public int? MozoId { get; set; }
    [Column("estado")] public string Estado { get; set; } = "Abierta";
    [Column("fecha_apertura")] public DateTime FechaApertura { get; set; }
    [Column("fecha_cierre")] public DateTime? FechaCierre { get; set; }
    [Column("subtotal", TypeName = "decimal(18,2)")] public decimal Subtotal { get; set; }
    [Column("importe_descuento", TypeName = "decimal(18,2)")] public decimal ImporteDescuento { get; set; }
    [Column("total", TypeName = "decimal(18,2)")] public decimal Total { get; set; }
    [Column("id_usuario_apertura")] public int UsuarioId { get; set; }
    [Column("id_usuario_cobro")] public int? UsuarioCobroId { get; set; }
    [Column("id_descuento")] public int? DescuentoId { get; set; }
    [Column("descuento_nombre")] public string? DescuentoNombre { get; set; }
    [Column("descuento_tipo")] public string? DescuentoTipo { get; set; }
    [Column("descuento_valor", TypeName = "decimal(18,2)")] public decimal? DescuentoValor { get; set; }
    [Column("version")] public long Version { get; set; } = 1;
    public Table Table { get; set; } = null!;
    public List<OrderItem> Items { get; set; } = [];
    public List<SalePayment> Payments { get; set; } = [];
    public List<KitchenCommand> Commands { get; set; } = [];
    public List<SaleJoinedTable> JoinedTables { get; set; } = [];
}

[Table("venta_items")]
public class OrderItem
{
    [Column("id_venta_item")] public int Id { get; set; }
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("id_producto")] public int ProductId { get; set; }
    [Column("producto_nombre")] public string ProductName { get; set; } = string.Empty;
    [Column("precio_unitario", TypeName = "decimal(18,2)")] public decimal UnitPrice { get; set; }
    [Column("cantidad", TypeName = "decimal(18,3)")] public decimal Quantity { get; set; }
    [Column("subtotal", TypeName = "decimal(18,2)")] public decimal Subtotal { get; set; }
    [Column("comentario")] public string? Comment { get; set; }
    [Column("estado")] public string Estado { get; set; } = "Activo";
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}

[Table("descuentos")]
public class Discount
{
    [Column("id_descuento")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("tipo")] public string Tipo { get; set; } = "Porcentaje";
    [Column("valor", TypeName = "decimal(18,2)")] public decimal Valor { get; set; }
    [Column("activo")] public bool Activo { get; set; } = true;
    [Column("vigente_desde")] public DateTime? VigenteDesde { get; set; }
    [Column("vigente_hasta")] public DateTime? VigenteHasta { get; set; }
}

[Table("tipos_cobro")]
public class PaymentType
{
    [Column("id_tipo_cobro")] public int Id { get; set; }
    [Column("id_empresa")] public int? IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("activo")] public bool Activo { get; set; } = true;
}

[Table("tarjetas")]
public class Card
{
    [Column("id_tarjeta")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("tipo_ajuste")] public string TipoAjuste { get; set; } = "SinAjuste";
    [Column("porcentaje", TypeName = "decimal(5,2)")] public decimal Porcentaje { get; set; }
    [Column("activa")] public bool Activa { get; set; } = true;
}

[Table("venta_pagos")]
public class SalePayment
{
    [Column("id_pago")] public int Id { get; set; }
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("id_tipo_cobro")] public int PaymentTypeId { get; set; }
    [Column("tipo_cobro_nombre")] public string PaymentTypeName { get; set; } = string.Empty;
    [Column("importe", TypeName = "decimal(18,2)")] public decimal Amount { get; set; }
    [Column("fecha")] public DateTime Fecha { get; set; }
    [Column("id_usuario")] public int UsuarioId { get; set; }
    [Column("referencia")] public string? Reference { get; set; }
}

[Table("comandas")]
public class KitchenCommand
{
    [Column("id_comanda")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("numero")] public int Numero { get; set; }
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("id_mesa")] public int TableId { get; set; }
    [Column("id_mozo")] public int? MozoId { get; set; }
    [Column("tipo")] public string Tipo { get; set; } = "Inicial";
    [Column("fecha")] public DateTime Fecha { get; set; }
    [Column("id_usuario")] public int UsuarioId { get; set; }
    public List<KitchenCommandLine> Lines { get; set; } = [];
}

[Table("comanda_renglones")]
public class KitchenCommandLine
{
    [Column("id_comanda_renglon")] public int Id { get; set; }
    [Column("id_comanda")] public int CommandId { get; set; }
    [Column("id_producto")] public int ProductId { get; set; }
    [Column("producto_nombre")] public string ProductName { get; set; } = string.Empty;
    [Column("variacion_cantidad", TypeName = "decimal(18,3)")] public decimal QuantityDelta { get; set; }
    [Column("cantidad_actual", TypeName = "decimal(18,3)")] public decimal CurrentQuantity { get; set; }
    [Column("comentario")] public string? Comment { get; set; }
}

[Table("venta_mesas_unidas")]
public class SaleJoinedTable
{
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("id_mesa")] public int TableId { get; set; }
}

[Table("venta_contadores")]
public class SaleCounter
{
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("ultimo_numero_venta")] public int LastSaleNumber { get; set; }
    [Column("ultimo_numero_comanda")] public int LastCommandNumber { get; set; }
}

public record SaleItemRequest([param: Range(1, int.MaxValue)] int ProductId, [param: Range(typeof(decimal), "0.001", "999999999999999.999")] decimal Quantity, [param: MaxLength(500)] string? Comment);
public record CreateSaleRequest([param: Range(1, int.MaxValue)] int TableId, int? WaiterId, List<SaleItemRequest>? Items);
public record UpdateSaleItemRequest([param: Range(typeof(decimal), "0.001", "999999999999999.999")] decimal Quantity, [param: MaxLength(500)] string? Comment, long? Version);
public record ApplyDiscountRequest(int? DiscountId, string? Name, string Type, decimal Value, long? Version);
public record PaymentRequest([param: Range(1, int.MaxValue)] int PaymentTypeId, [param: Range(typeof(decimal), "0.01", "9999999999999999.99")] decimal Amount, [param: MaxLength(500)] string? Reference);
public record AddPaymentsRequest([param: Required, MinLength(1)] List<PaymentRequest> Payments, long? Version);
public record MoveTableRequest([param: Range(1, int.MaxValue)] int TableId, long? Version);
public record JoinTableRequest([param: Range(1, int.MaxValue)] int TableId, long? Version);
public class LegacyOrderRequest { public int Id { get; set; } public int TableId { get; set; } public int UserId { get; set; } public List<LegacyOrderItemRequest> Items { get; set; } = []; public decimal Total { get; set; } public DateTime CreatedAt { get; set; } }
public class LegacyOrderItemRequest { public int Id { get; set; } public int ProductId { get; set; } public string? Name { get; set; } public decimal Price { get; set; } public decimal Quantity { get; set; } public string? Comment { get; set; } public int ResolvedProductId => ProductId > 0 ? ProductId : Id; }
public class DiscountRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = string.Empty;
    [MaxLength(500)] public string? Description { get; set; }
    [Required] public string Type { get; set; } = "Porcentaje";
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal Value { get; set; }
    public DateTime? ValidFrom { get; set; }
    public DateTime? ValidUntil { get; set; }
}

public class CardRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = string.Empty;
    [MaxLength(500)] public string? Description { get; set; }
    [Required] public string AdjustmentType { get; set; } = "SinAjuste";
    [Range(typeof(decimal), "0", "100")] public decimal Percentage { get; set; }
}

public class SalesCatalogStatusRequest { public bool Active { get; set; } }

public record DiscountCatalogDto(int Id, string Name, string? Description, string Type, decimal Value, bool Active, DateTime? ValidFrom, DateTime? ValidUntil);
public record CardDto(int Id, string Name, string? Description, string AdjustmentType, decimal Percentage, bool Active);

public class SaleDto
{
    public int Id { get; set; } public int Number { get; set; } public int TableId { get; set; }
    public int? WaiterId { get; set; } public string Status { get; set; } = string.Empty;
    public DateTime OpenedAt { get; set; } public DateTime? ClosedAt { get; set; }
    public decimal Subtotal { get; set; } public decimal DiscountAmount { get; set; } public decimal Total { get; set; }
    public long Version { get; set; } public List<SaleItemDto> Items { get; set; } = [];
    public object? Discount { get; set; } public List<object> Payments { get; set; } = []; public List<int> JoinedTableIds { get; set; } = [];
}
public record SaleItemDto(int Id, int ProductId, string Name, decimal UnitPrice, decimal Quantity, decimal Subtotal, string? Comment, string Status);
public record CommandLineDto(int ProductId, string Name, decimal QuantityDelta, decimal CurrentQuantity, string? Comment);
public record CommandDto(int Id, int Number, string Type, DateTime Date, int TableId, int? WaiterId, List<CommandLineDto> Lines);
