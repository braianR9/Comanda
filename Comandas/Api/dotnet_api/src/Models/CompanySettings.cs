using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
namespace BarIceCreamShop.Api.Models;
[Table("empresa_configuracion")]
public class CompanySettings
{
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("direccion")] public string Address { get; set; } = "";
    [Column("web")] public string Website { get; set; } = "";
    [Column("facturacion", TypeName="jsonb")] public string BillingJson { get; set; } = "{}";
    [Column("version")] public int Version { get; set; } = 1;
    [Column("id_usuario_modificacion")] public int UpdatedBy { get; set; }
    [Column("fecha_modificacion")] public DateTime UpdatedAt { get; set; }
}
public class BillingSettings
{
    [MaxLength(200)] public string LegalName { get; set; } = "";
    [MaxLength(20)] public string Cuit { get; set; } = "";
    [MaxLength(80)] public string TaxCondition { get; set; } = "";
    [MaxLength(300)] public string FiscalAddress { get; set; } = "";
    [MaxLength(100)] public string City { get; set; } = "";
    [MaxLength(100)] public string Province { get; set; } = "";
    [MaxLength(15)] public string PostalCode { get; set; } = "";
    [MaxLength(50)] public string GrossIncomeRegistration { get; set; } = "";
    public DateOnly? ActivityStart { get; set; }
    public string Environment { get; set; } = "Homologacion";
    [Range(1,99999)] public int? PointOfSale { get; set; }
    [Range(1,3)] public int Concept { get; set; } = 1;
    /// "Manual": se factura con el botón Facturar. "Automatico": al cobrar cada venta.
    public string InvoicingMode { get; set; } = "Manual";
}
public class CompanySettingsRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = "";
    [MaxLength(150)] public string Email { get; set; } = "";
    [MaxLength(50)] public string Phone { get; set; } = "";
    [MaxLength(300)] public string Address { get; set; } = "";
    [MaxLength(200)] public string Website { get; set; } = "";
    public int Version { get; set; }
    [Required] public BillingSettings Billing { get; set; } = new();
}
