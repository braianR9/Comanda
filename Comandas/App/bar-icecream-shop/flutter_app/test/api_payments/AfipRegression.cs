using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.Extensions.Logging.Abstractions;

/// Cálculos de facturación sin AFIP y, con --live, comunicación real con homologación.
static class AfipRegression
{
    public static async Task Run(bool live)
    {
        // IVA: un total con descuento/recargo se reparte por alícuota y cierra al centavo.
        var (net, vat, detail) = InvoiceService.SplitVat(1000m, [(600m, 21m), (400m, 10.5m)], discriminate: true);
        Require(net + vat == 1000m, "neto + IVA igual al total");
        Require(detail.Count == 2 && detail.Sum(d => d.BaseAmount + d.Amount) == 1000m, "alícuotas suman el total");
        var general = detail.Single(d => d.Id == 5);
        Require(general.BaseAmount == 495.87m && general.Amount == 104.13m, "21% sobre $600 brutos");
        Require(detail.Single(d => d.Id == 4).BaseAmount == 361.99m, "10,5% sobre $400 brutos");

        var (cNet, cVat, cDetail) = InvoiceService.SplitVat(999.99m, [(1000m, 21m)], discriminate: false);
        Require(cNet == 999.99m && cVat == 0 && cDetail.Count == 0, "factura C sin IVA discriminado");

        var (_, _, rounding) = InvoiceService.SplitVat(100m, [(1m, 21m), (1m, 21m), (1m, 10.5m)], discriminate: true);
        Require(rounding.Sum(d => d.BaseAmount + d.Amount) == 100m, "redondeo absorbido por la alícuota mayor");

        Expect<InvoiceException>(() => InvoiceService.SplitVat(0, [(10m, 21m)], true), "venta en $0");
        Expect<InvoiceException>(() => InvoiceService.SplitVat(10, [(10m, 19m)], true), "alícuota inexistente");

        // Tipo de comprobante según emisor y receptor.
        var ri = new BillingSettings { TaxCondition = "IVA Responsable Inscripto" };
        var mono = new BillingSettings { TaxCondition = "Responsable Monotributo" };
        Require(InvoiceService.InvoiceType(ri, AfipCodes.CondResponsableInscripto) == AfipCodes.FacturaA, "RI a RI: A");
        Require(InvoiceService.InvoiceType(ri, AfipCodes.CondMonotributo) == AfipCodes.FacturaA, "RI a monotributo: A");
        Require(InvoiceService.InvoiceType(ri, AfipCodes.CondConsumidorFinal) == AfipCodes.FacturaB, "RI a consumidor final: B");
        Require(InvoiceService.InvoiceType(mono, AfipCodes.CondResponsableInscripto) == AfipCodes.FacturaC, "monotributo: C");
        Require(AfipCodes.CreditNoteFor(AfipCodes.FacturaB) == AfipCodes.NotaCreditoB, "nota de crédito B");

        Require(InvoiceService.ValidCuit("20111111112"), "CUIT válido");
        Require(!InvoiceService.ValidCuit("20111111113"), "CUIT con dígito verificador erróneo");

        // QR: JSON en base64 con los campos de la especificación de AFIP.
        var invoice = new Invoice
        {
            Status = "Autorizado", Cae = "75123456789012", Date = new DateOnly(2026, 10, 22), PointOfSale = 3,
            Type = AfipCodes.FacturaB, Number = 15, Total = 1234.5m, DocType = AfipCodes.DocSinIdentificar, DocNumber = 0,
        };
        var url = InvoiceService.QrUrl(invoice, "20111111112")!;
        Require(url.StartsWith("https://www.afip.gob.ar/fe/qr/?p="), "URL del QR");
        using (var qr = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(url.Split("?p=")[1]))))
        {
            Require(qr.RootElement.GetProperty("cuit").GetInt64() == 20111111112, "QR: CUIT numérico");
            Require(qr.RootElement.GetProperty("codAut").GetInt64() == 75123456789012, "QR: CAE numérico");
            Require(qr.RootElement.GetProperty("fecha").GetString() == "2026-10-22", "QR: fecha");
        }
        Require(InvoiceService.Format(invoice) == "00003-00000015", "formato de número");
        Console.WriteLine("AFIP: cálculos OK");

        if (!live) return;
        var client = new AfipClient(new HttpClient { Timeout = TimeSpan.FromSeconds(30) }, NullLogger<AfipClient>.Instance);
        Console.WriteLine("WSFEv1 homologación: " + await client.DummyAsync("Homologacion"));

        // Un certificado autofirmado prueba la firma CMS y el sobre SOAP: AFIP debe rechazarlo por no confiable.
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=prueba, SERIALNUMBER=CUIT 20111111112, O=Prueba, C=AR", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
        try
        {
            await client.LoginAsync("Homologacion", cert, key, "wsfe");
            throw new Exception("WSAA aceptó un certificado autofirmado.");
        }
        catch (AfipException e) when (!e.Transient)
        {
            Console.WriteLine("WSAA homologación (rechazo esperado): " + e.Message);
        }
        Console.WriteLine("AFIP: comunicación OK");
    }

    private static void Require(bool ok, string description)
    {
        if (!ok) throw new Exception("Falló: " + description);
    }

    private static void Expect<T>(Action action, string description) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception("Se esperaba un error: " + description);
    }
}
