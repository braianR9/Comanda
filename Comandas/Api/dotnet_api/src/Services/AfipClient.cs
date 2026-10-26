using System.Globalization;
using System.Security.Cryptography;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Xml.Linq;
using BarIceCreamShop.Api.Models;
namespace BarIceCreamShop.Api.Services;

public record AfipAuth(string Token, string Sign, long Cuit);
public record AfipTicket(string Token, string Sign, DateTime ExpiresAt);
public record AfipMessage(int Code, string Text);

public record AfipInvoiceRequest(int PointOfSale, int Type, long Number, int Concept, int DocType, long DocNumber,
    DateOnly Date, decimal Total, decimal Net, decimal Vat, int ReceiverVatCondition, IReadOnlyList<InvoiceVat> VatDetail,
    (int Type, int PointOfSale, long Number, long Cuit, DateOnly Date)? Associated);

public record AfipInvoiceResult(bool Approved, string? Cae, DateOnly? CaeExpiresAt, List<AfipMessage> Messages);

/// Comprobante ya registrado en AFIP (FECompConsultar).
public record AfipExistingInvoice(string Cae, DateOnly? CaeExpiresAt, decimal Total, long DocNumber, DateOnly Date);

public sealed class AfipException(string message, bool transient = false) : Exception(message)
{ public bool Transient { get; } = transient; }

/// Cliente SOAP de WSAA (autenticación) y WSFEv1 (factura electrónica) de AFIP/ARCA.
public class AfipClient(HttpClient http, ILogger<AfipClient> logger)
{
    private static readonly XNamespace Soap = "http://schemas.xmlsoap.org/soap/envelope/";
    private static readonly XNamespace Fe = "http://ar.gov.afip.dif.FEV1/";
    private static readonly TimeZoneInfo Argentina = FindArgentinaZone();

    private static string WsaaUrl(string env) => env == "Produccion"
        ? "https://wsaa.afip.gov.ar/ws/services/LoginCms"
        : "https://wsaahomo.afip.gov.ar/ws/services/LoginCms";
    private static string WsfeUrl(string env) => env == "Produccion"
        ? "https://servicios1.afip.gov.ar/wsfev1/service.asmx"
        : "https://wswhomo.afip.gov.ar/wsfev1/service.asmx";

    public static DateTime ArgentinaNow() => TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Argentina);

    // ─── WSAA ───────────────────────────────────────────────────────────────
    public async Task<AfipTicket> LoginAsync(string env, X509Certificate2 certificate, RSA key, string service, CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow.ToOffset(TimeSpan.FromHours(-3));
        var tra = new XDocument(new XElement("loginTicketRequest", new XAttribute("version", "1.0"),
            new XElement("header",
                new XElement("uniqueId", now.ToUnixTimeSeconds()),
                new XElement("generationTime", now.AddMinutes(-10).ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture)),
                new XElement("expirationTime", now.AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture))),
            new XElement("service", service)));
        var cms = new SignedCms(new ContentInfo(Encoding.UTF8.GetBytes(tra.ToString(SaveOptions.DisableFormatting))), detached: false);
        cms.ComputeSignature(new CmsSigner(SubjectIdentifierType.IssuerAndSerialNumber, certificate, key) { IncludeOption = X509IncludeOption.EndCertOnly });
        XNamespace wsaa = "http://wsaa.view.sua.dvadac.desein.afip.gov";
        var envelope = new XElement(Soap + "Envelope", new XAttribute(XNamespace.Xmlns + "soapenv", Soap), new XAttribute(XNamespace.Xmlns + "wsaa", wsaa),
            new XElement(Soap + "Header"),
            new XElement(Soap + "Body", new XElement(wsaa + "loginCms", new XElement(wsaa + "in0", Convert.ToBase64String(cms.Encode())))));
        var body = await PostAsync(WsaaUrl(env), "\"\"", envelope, ct);
        var result = body.Descendants().FirstOrDefault(e => e.Name.LocalName == "loginCmsReturn")?.Value
            ?? throw new AfipException("WSAA no devolvió el ticket de acceso.");
        var ticket = XDocument.Parse(result);
        var token = ticket.Descendants("token").Single().Value;
        var sign = ticket.Descendants("sign").Single().Value;
        var expires = DateTimeOffset.Parse(ticket.Descendants("expirationTime").Single().Value, CultureInfo.InvariantCulture).UtcDateTime;
        return new AfipTicket(token, sign, expires);
    }

    // ─── WSFEv1 ─────────────────────────────────────────────────────────────
    public async Task<string> DummyAsync(string env, CancellationToken ct = default)
    {
        var result = await CallFeAsync(env, "FEDummy", [], ct);
        string Value(string name) => result.Descendants(Fe + name).FirstOrDefault()?.Value ?? "?";
        return $"App: {Value("AppServer")} · Base: {Value("DbServer")} · Autenticación: {Value("AuthServer")}";
    }

    public async Task<long> LastAuthorizedAsync(string env, AfipAuth auth, int pointOfSale, int type, CancellationToken ct = default)
    {
        var result = await CallFeAsync(env, "FECompUltimoAutorizado",
            [AuthElement(auth), new XElement(Fe + "PtoVta", pointOfSale), new XElement(Fe + "CbteTipo", type)], ct);
        ThrowOnErrors(result);
        return long.Parse(result.Element(Fe + "CbteNro")?.Value ?? "0", CultureInfo.InvariantCulture);
    }

    public async Task<AfipExistingInvoice?> FindAsync(string env, AfipAuth auth, int pointOfSale, int type, long number, CancellationToken ct = default)
    {
        var result = await CallFeAsync(env, "FECompConsultar",
            [AuthElement(auth), new XElement(Fe + "FeCompConsReq",
                new XElement(Fe + "CbteTipo", type), new XElement(Fe + "CbteNro", number), new XElement(Fe + "PtoVta", pointOfSale))], ct);
        var errors = Messages(result.Element(Fe + "Errors"), "Err");
        if (errors.Any(e => e.Code == 602)) return null; // No existe el comprobante.
        if (errors.Count > 0) throw new AfipException(Describe(errors));
        var get = result.Element(Fe + "ResultGet") ?? throw new AfipException("AFIP no devolvió el comprobante consultado.");
        var cae = get.Element(Fe + "CodAutorizacion")?.Value;
        if (string.IsNullOrWhiteSpace(cae)) return null;
        return new AfipExistingInvoice(cae, ParseDate(get.Element(Fe + "FchVto")?.Value),
            decimal.Parse(get.Element(Fe + "ImpTotal")?.Value ?? "0", CultureInfo.InvariantCulture),
            long.Parse(get.Element(Fe + "DocNro")?.Value ?? "0", CultureInfo.InvariantCulture),
            ParseDate(get.Element(Fe + "CbteFch")?.Value) ?? default);
    }

    public async Task<AfipInvoiceResult> AuthorizeAsync(string env, AfipAuth auth, AfipInvoiceRequest r, CancellationToken ct = default)
    {
        // El orden de los elementos respeta la secuencia del WSDL de FEDetRequest.
        var detail = new XElement(Fe + "FECAEDetRequest",
            new XElement(Fe + "Concepto", r.Concept),
            new XElement(Fe + "DocTipo", r.DocType),
            new XElement(Fe + "DocNro", r.DocNumber),
            new XElement(Fe + "CbteDesde", r.Number),
            new XElement(Fe + "CbteHasta", r.Number),
            new XElement(Fe + "CbteFch", Date(r.Date)),
            new XElement(Fe + "ImpTotal", Money(r.Total)),
            new XElement(Fe + "ImpTotConc", "0.00"),
            new XElement(Fe + "ImpNeto", Money(r.Net)),
            new XElement(Fe + "ImpOpEx", "0.00"),
            new XElement(Fe + "ImpTrib", "0.00"),
            new XElement(Fe + "ImpIVA", Money(r.Vat)));
        if (r.Concept != 1)
        {
            // Servicios: el período facturado es el día de la venta.
            detail.Add(new XElement(Fe + "FchServDesde", Date(r.Date)), new XElement(Fe + "FchServHasta", Date(r.Date)),
                new XElement(Fe + "FchVtoPago", Date(r.Date)));
        }
        detail.Add(new XElement(Fe + "MonId", "PES"), new XElement(Fe + "MonCotiz", "1"),
            new XElement(Fe + "CondicionIVAReceptorId", r.ReceiverVatCondition));
        if (r.Associated is { } a)
            detail.Add(new XElement(Fe + "CbtesAsoc", new XElement(Fe + "CbteAsoc",
                new XElement(Fe + "Tipo", a.Type), new XElement(Fe + "PtoVta", a.PointOfSale), new XElement(Fe + "Nro", a.Number),
                new XElement(Fe + "Cuit", a.Cuit), new XElement(Fe + "CbteFch", Date(a.Date)))));
        if (r.VatDetail.Count > 0)
            detail.Add(new XElement(Fe + "Iva", r.VatDetail.Select(v => new XElement(Fe + "AlicIva",
                new XElement(Fe + "Id", v.Id), new XElement(Fe + "BaseImp", Money(v.BaseAmount)), new XElement(Fe + "Importe", Money(v.Amount))))));

        var request = new XElement(Fe + "FeCAEReq",
            new XElement(Fe + "FeCabReq", new XElement(Fe + "CantReg", 1), new XElement(Fe + "PtoVta", r.PointOfSale), new XElement(Fe + "CbteTipo", r.Type)),
            new XElement(Fe + "FeDetReq", detail));
        var result = await CallFeAsync(env, "FECAESolicitar", [AuthElement(auth), request], ct);

        var messages = Messages(result.Element(Fe + "Errors"), "Err");
        var det = result.Descendants(Fe + "FECAEDetResponse").FirstOrDefault();
        if (det != null) messages.AddRange(Messages(det.Element(Fe + "Observaciones"), "Obs"));
        messages.AddRange(Messages(result.Element(Fe + "Events"), "Evt"));
        var approved = det?.Element(Fe + "Resultado")?.Value == "A";
        var cae = det?.Element(Fe + "CAE")?.Value;
        return new AfipInvoiceResult(approved && !string.IsNullOrWhiteSpace(cae), string.IsNullOrWhiteSpace(cae) ? null : cae,
            ParseDate(det?.Element(Fe + "CAEFchVto")?.Value), messages);
    }

    public static string Describe(IEnumerable<AfipMessage> messages) => string.Join(" | ", messages.Select(m => $"{m.Code}: {m.Text}"));

    // ─── Infraestructura SOAP ──────────────────────────────────────────────
    private async Task<XElement> CallFeAsync(string env, string method, XElement[] content, CancellationToken ct)
    {
        var envelope = new XElement(Soap + "Envelope", new XAttribute(XNamespace.Xmlns + "soap", Soap),
            new XElement(Soap + "Body", new XElement(Fe + method, content)));
        var body = await PostAsync(WsfeUrl(env), $"\"http://ar.gov.afip.dif.FEV1/{method}\"", envelope, ct);
        return body.Descendants(Fe + method + "Result").FirstOrDefault()
            ?? throw new AfipException($"AFIP no devolvió la respuesta de {method}.");
    }

    private async Task<XElement> PostAsync(string url, string action, XElement envelope, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(envelope.ToString(SaveOptions.DisableFormatting), Encoding.UTF8, "text/xml"),
        };
        request.Headers.TryAddWithoutValidation("SOAPAction", action);
        HttpResponseMessage response;
        try { response = await http.SendAsync(request, ct); }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            logger.LogWarning(e, "Sin respuesta de AFIP en {Url}.", url);
            throw new AfipException("AFIP no responde. Revisá la conexión a internet o intentá más tarde.", transient: true);
        }
        using (response)
        {
            var text = await response.Content.ReadAsStringAsync(ct);
            XDocument document;
            try { document = XDocument.Parse(text); }
            catch (System.Xml.XmlException)
            {
                logger.LogWarning("Respuesta no XML de AFIP ({Status}): {Body}", (int)response.StatusCode, text.Length > 500 ? text[..500] : text);
                throw new AfipException($"AFIP respondió con un error ({(int)response.StatusCode}). Intentá más tarde.", transient: true);
            }
            var fault = document.Descendants().FirstOrDefault(e => e.Name.LocalName == "Fault");
            if (fault != null)
            {
                var code = fault.Elements().FirstOrDefault(e => e.Name.LocalName == "faultcode")?.Value ?? "";
                var message = fault.Elements().FirstOrDefault(e => e.Name.LocalName == "faultstring")?.Value ?? "Error de AFIP.";
                throw new AfipException(code.Contains("alreadyAuthenticated")
                    ? "AFIP ya entregó un acceso vigente que este sistema no tiene guardado. Esperá unos minutos (hasta 12 h) e intentá de nuevo."
                    : $"AFIP: {message}");
            }
            return document.Root?.Element(Soap + "Body") ?? throw new AfipException("Respuesta de AFIP inválida.");
        }
    }

    private static XElement AuthElement(AfipAuth auth) => new(Fe + "Auth",
        new XElement(Fe + "Token", auth.Token), new XElement(Fe + "Sign", auth.Sign), new XElement(Fe + "Cuit", auth.Cuit));

    private static List<AfipMessage> Messages(XElement? container, string item) => container == null ? [] :
        container.Elements(Fe + item).Select(e => new AfipMessage(
            int.TryParse(e.Element(Fe + "Code")?.Value, out var code) ? code : 0, e.Element(Fe + "Msg")?.Value ?? "")).ToList();

    private static void ThrowOnErrors(XElement result)
    {
        var errors = Messages(result.Element(Fe + "Errors"), "Err");
        if (errors.Count > 0) throw new AfipException(Describe(errors));
    }

    private static string Money(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero).ToString("0.00", CultureInfo.InvariantCulture);
    private static string Date(DateOnly value) => value.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
    private static DateOnly? ParseDate(string? value) =>
        DateOnly.TryParseExact(value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : null;

    private static TimeZoneInfo FindArgentinaZone()
    {
        foreach (var id in new[] { "America/Argentina/Buenos_Aires", "Argentina Standard Time" })
            try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch (TimeZoneNotFoundException) { }
        return TimeZoneInfo.CreateCustomTimeZone("ART", TimeSpan.FromHours(-3), "ART", "ART");
    }
}
