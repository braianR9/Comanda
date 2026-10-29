using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("venta_anulaciones")]
public class SaleVoid
{
    [Key, Column("id_venta")] public int OrderId { get; set; }
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("id_sucursal")] public int BranchId { get; set; }
    [Column("id_caja")] public int CashId { get; set; }
    [Column("id_usuario")] public int UserId { get; set; }
    [Column("fecha")] public DateTime Date { get; set; }
    [Column("motivo")] public string Reason { get; set; } = "";
    [Column("total_devuelto")] public decimal Refunded { get; set; }
}
[Table("venta_devoluciones")]
public class SaleRefund
{
    [Column("id")] public int Id { get; set; }
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("id_pago_original")] public int OriginalPaymentId { get; set; }
    [Column("medio_pago")] public string PaymentTypeName { get; set; } = "";
    [Column("importe")] public decimal Amount { get; set; }
}
public class VoidSaleRequest
{
    [Required, MinLength(3), MaxLength(500)] public string Reason { get; set; } = "";
    [Range(1, long.MaxValue)] public long Version { get; set; }
}
