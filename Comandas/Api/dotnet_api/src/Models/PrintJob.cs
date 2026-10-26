using System;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    [Table("trabajos_impresion")]
    public class PrintJob
    {
        [Column("id_trabajo_impresion")] public int Id { get; set; }
        [Column("id_venta")] public int? OrderId { get; set; }
        [Column("id_caja")] public int? CajaId { get; set; }
        [Column("id_impresora")] public string PrinterId { get; set; } = string.Empty;
        [Column("fecha_creacion")] public DateTime CreatedAt { get; set; }
        [Column("estado")] public string Status { get; set; } = "Pendiente";
        [Column("tipo")] public string JobType { get; set; } = "Comanda";
        [Column("id_impresora_configuracion")] public int? PrinterConfigurationId { get; set; }
        /// Comprobante electrónico a imprimir; si falta, se usa la factura vigente de la venta.
        [Column("id_comprobante")] public int? InvoiceId { get; set; }
        [Column("id_usuario")] public int? UserId { get; set; }
        [Column("reimpresion")] public bool Reprint { get; set; }
    }
}
