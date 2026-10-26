using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
namespace BarIceCreamShop.Api.Models;

[Table("afip_credenciales")]
public class AfipCredential
{
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("ambiente")] public string Environment { get; set; } = "Homologacion";
    [Column("clave_privada")] public byte[] EncryptedKey { get; set; } = [];
    [Column("csr")] public string Csr { get; set; } = "";
    [Column("certificado")] public string? Certificate { get; set; }
    [Column("certificado_sujeto")] public string? CertificateSubject { get; set; }
    [Column("certificado_vence")] public DateTime? CertificateExpiresAt { get; set; }
    [Column("fecha_creacion")] public DateTime CreatedAt { get; set; }
    [Column("fecha_certificado")] public DateTime? CertificateUploadedAt { get; set; }
}

[Table("afip_tokens")]
public class AfipToken
{
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("ambiente")] public string Environment { get; set; } = "";
    [Column("servicio")] public string Service { get; set; } = "";
    [Column("token")] public string Token { get; set; } = "";
    [Column("sign")] public string Sign { get; set; } = "";
    [Column("vence")] public DateTime ExpiresAt { get; set; }
}

[Table("comprobantes")]
public class Invoice
{
    [Column("id_comprobante")] public int Id { get; set; }
    [Column("id_empresa")] public int CompanyId { get; set; }
    [Column("id_sucursal")] public int BranchId { get; set; }
    [Column("id_venta")] public int OrderId { get; set; }
    [Column("ambiente")] public string Environment { get; set; } = "Homologacion";
    [Column("tipo_comprobante")] public int Type { get; set; }
    [Column("punto_venta")] public int PointOfSale { get; set; }
    [Column("numero")] public long Number { get; set; }
    [Column("fecha")] public DateOnly Date { get; set; }
    [Column("concepto")] public int Concept { get; set; }
    [Column("doc_tipo")] public int DocType { get; set; }
    [Column("doc_nro")] public long DocNumber { get; set; }
    [Column("receptor_nombre")] public string ReceiverName { get; set; } = "";
    [Column("receptor_condicion_iva")] public int ReceiverVatCondition { get; set; }
    [Column("id_cliente")] public int? CustomerId { get; set; }
    [Column("imp_total", TypeName = "decimal(15,2)")] public decimal Total { get; set; }
    [Column("imp_neto", TypeName = "decimal(15,2)")] public decimal Net { get; set; }
    [Column("imp_iva", TypeName = "decimal(15,2)")] public decimal Vat { get; set; }
    [Column("iva", TypeName = "jsonb")] public string VatJson { get; set; } = "[]";
    [Column("estado")] public string Status { get; set; } = "Procesando";
    [Column("cae")] public string? Cae { get; set; }
    [Column("cae_vence")] public DateOnly? CaeExpiresAt { get; set; }
    [Column("mensajes")] public string Messages { get; set; } = "";
    /// Motivo de una nota de crédito, indicado por quien la emitió.
    [Column("motivo")] public string Reason { get; set; } = "";
    [Column("id_comprobante_asociado")] public int? AssociatedInvoiceId { get; set; }
    [Column("id_nota_credito")] public int? CreditNoteId { get; set; }
    [Column("id_usuario")] public int UserId { get; set; }
    [Column("fecha_creacion")] public DateTime CreatedAt { get; set; }
    [Column("fecha_autorizacion")] public DateTime? AuthorizedAt { get; set; }

    [NotMapped] public bool IsCreditNote => AfipCodes.IsCreditNote(Type);
    /// Factura que anula una nota de crédito, para imprimirla ("Factura C 00001-00000001").
    [NotMapped] public string? AssociatedLabel { get; set; }
}

/// Alícuota de IVA de un comprobante, en el formato de AFIP (AlicIva).
public record InvoiceVat(int Id, decimal Rate, decimal BaseAmount, decimal Amount);

public class InvoiceRequest
{
    /// Cliente registrado; si se omite, se factura a consumidor final.
    public int? CustomerId { get; set; }
    /// Para identificar a un consumidor final sin darlo de alta (DNI, CUIT, CUIL).
    [MaxLength(30)] public string? DocumentType { get; set; }
    [MaxLength(20)] public string? DocumentNumber { get; set; }
    [MaxLength(200)] public string? Name { get; set; }
}

public class CreditNoteRequest
{
    [Required(ErrorMessage = "Indicá el motivo de la nota de crédito."), MaxLength(500)] public string Reason { get; set; } = "";
}

public class CertificateRequestInput
{
    [Required] public string Environment { get; set; } = "Homologacion";
    /// Alias con que se identificará el certificado en AFIP.
    [Required, MaxLength(50)] public string Alias { get; set; } = "comandas";
}

public class CertificateUploadInput
{
    [Required] public string Environment { get; set; } = "Homologacion";
    [Required, MaxLength(20000)] public string Certificate { get; set; } = "";
}

public record InvoiceDto(int Id, int OrderId, string Environment, int Type, string TypeName, int PointOfSale, long Number,
    string FormattedNumber, DateOnly Date, int DocType, long DocNumber, string ReceiverName, int ReceiverVatCondition,
    decimal Total, decimal Net, decimal Vat, List<InvoiceVat> VatDetail, string Status, string? Cae, DateOnly? CaeExpiresAt,
    string Messages, int? AssociatedInvoiceId, int? CreditNoteId, DateTime CreatedAt, string? QrUrl,
    DateTime? AuthorizedAt, int UserId, string UserName, string Reason);

public sealed class InvoiceException(string message, int statusCode = 400) : Exception(message)
{ public int StatusCode { get; } = statusCode; }

/// Códigos de las tablas de parámetros de WSFEv1.
public static class AfipCodes
{
    public const int FacturaA = 1, NotaCreditoA = 3, FacturaB = 6, NotaCreditoB = 8, FacturaC = 11, NotaCreditoC = 13;
    public const int DocCuit = 80, DocCuil = 86, DocCdi = 87, DocPasaporte = 94, DocDni = 96, DocSinIdentificar = 99;
    public const int CondResponsableInscripto = 1, CondExento = 4, CondConsumidorFinal = 5, CondMonotributo = 6, CondNoCategorizado = 7;

    public static bool IsInvoice(int type) => type is FacturaA or FacturaB or FacturaC;
    public static bool IsCreditNote(int type) => type is NotaCreditoA or NotaCreditoB or NotaCreditoC;
    public static int CreditNoteFor(int invoiceType) => invoiceType switch
    {
        FacturaA => NotaCreditoA, FacturaB => NotaCreditoB, FacturaC => NotaCreditoC,
        _ => throw new InvoiceException("Solo se puede emitir nota de crédito sobre una factura."),
    };
    public static string TypeName(int type) => type switch
    {
        FacturaA => "Factura A", FacturaB => "Factura B", FacturaC => "Factura C",
        NotaCreditoA => "Nota de crédito A", NotaCreditoB => "Nota de crédito B", NotaCreditoC => "Nota de crédito C",
        _ => $"Comprobante {type}",
    };
    public static string Letter(int type) => type switch
    {
        FacturaA or NotaCreditoA => "A", FacturaB or NotaCreditoB => "B", _ => "C",
    };

    /// Id de alícuota de AFIP para un porcentaje de IVA.
    public static int VatId(decimal rate) => rate switch
    {
        0m => 3, 2.5m => 9, 5m => 8, 10.5m => 4, 21m => 5, 27m => 6,
        _ => throw new InvoiceException($"La alícuota de IVA {rate:0.##}% no es válida para AFIP. Revisá el maestro de alícuotas.", 409),
    };

    public static int DocType(string? name) => (name ?? "").Trim().ToUpperInvariant() switch
    {
        "CUIT" => DocCuit, "CUIL" => DocCuil, "CDI" => DocCdi, "DNI" => DocDni, "PASAPORTE" => DocPasaporte,
        "" or "SIN IDENTIFICAR" => DocSinIdentificar,
        _ => throw new InvoiceException($"El tipo de documento '{name}' no se puede usar para facturar."),
    };

    /// Condición IVA del receptor (RG 5616) a partir del texto del maestro de clientes.
    public static int VatCondition(string? name)
    {
        var value = (name ?? "").Trim().ToLowerInvariant();
        if (value.Contains("inscripto")) return CondResponsableInscripto;
        if (value.Contains("monotrib")) return CondMonotributo;
        if (value.Contains("exento")) return CondExento;
        if (value.Contains("consumidor") || value.Length == 0) return CondConsumidorFinal;
        return CondNoCategorizado;
    }
}
