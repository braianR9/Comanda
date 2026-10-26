using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
namespace BarIceCreamShop.Api.Services;

/// Certificado digital de AFIP por empresa y ambiente, y ticket de acceso de WSAA.
public class AfipCredentialService(AppDbContext db, AfipClient afip, IConfiguration configuration)
{
    private const string Service = "wsfe";

    public async Task<object> StatusAsync(int company)
    {
        var rows = await db.AfipCredentials.AsNoTracking().Where(x => x.CompanyId == company).ToListAsync();
        object Describe(string env)
        {
            var row = rows.SingleOrDefault(x => x.Environment == env);
            return new
            {
                environment = env,
                hasRequest = row != null,
                hasCertificate = row?.Certificate != null,
                subject = row?.CertificateSubject,
                expiresAt = row?.CertificateExpiresAt,
                expired = row?.CertificateExpiresAt < DateTime.UtcNow,
                csr = row?.Certificate == null ? row?.Csr : null,
            };
        }
        return new { encryptionConfigured = EncryptionKey() != null, homologacion = Describe("Homologacion"), produccion = Describe("Produccion") };
    }

    /// Genera una clave RSA nueva y el pedido de certificado (CSR) para subir a AFIP.
    public async Task<object> CreateRequestAsync(int company, CertificateRequestInput input)
    {
        var env = ValidEnvironment(input.Environment);
        var billing = await BillingAsync(company);
        if (billing.Cuit.Length != 11) throw new InvoiceException("Completá el CUIT de la empresa en Facturación antes de generar el certificado.");
        if (string.IsNullOrWhiteSpace(billing.LegalName)) throw new InvoiceException("Completá la razón social en Facturación antes de generar el certificado.");
        var alias = new string(input.Alias.Trim().Where(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_').ToArray());
        if (alias.Length == 0) throw new InvoiceException("El alias solo admite letras, números, guiones y guiones bajos.");

        using var rsa = RSA.Create(2048);
        var subject = new X500DistinguishedNameBuilder();
        subject.AddCountryOrRegion("AR");
        subject.AddOrganizationName(Ascii(billing.LegalName));
        subject.AddCommonName(alias);
        subject.Add("2.5.4.5", $"CUIT {billing.Cuit}", System.Formats.Asn1.UniversalTagNumber.PrintableString); // serialNumber
        var csr = new CertificateRequest(subject.Build(), rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1).CreateSigningRequestPem();

        var row = await db.AfipCredentials.SingleOrDefaultAsync(x => x.CompanyId == company && x.Environment == env);
        if (row == null) { row = new AfipCredential { CompanyId = company, Environment = env }; db.AfipCredentials.Add(row); }
        row.EncryptedKey = Encrypt(rsa.ExportPkcs8PrivateKey());
        row.Csr = csr; row.Certificate = null; row.CertificateSubject = null; row.CertificateExpiresAt = null;
        row.CreatedAt = DateTime.UtcNow; row.CertificateUploadedAt = null;
        await db.AfipTokens.Where(x => x.CompanyId == company && x.Environment == env).ExecuteDeleteAsync();
        await db.SaveChangesAsync();
        return new { environment = env, csr, fileName = $"{alias}.csr" };
    }

    /// Guarda el certificado que devolvió AFIP; debe corresponder a la última clave generada.
    public async Task<object> UploadCertificateAsync(int company, CertificateUploadInput input)
    {
        var env = ValidEnvironment(input.Environment);
        var row = await db.AfipCredentials.SingleOrDefaultAsync(x => x.CompanyId == company && x.Environment == env)
            ?? throw new InvoiceException("Primero generá el pedido de certificado (CSR) para este ambiente.", 409);
        X509Certificate2 certificate;
        try
        {
            var text = input.Certificate.Trim();
            certificate = text.Contains("BEGIN CERTIFICATE")
                ? X509Certificate2.CreateFromPem(text)
                : X509CertificateLoader.LoadCertificate(Convert.FromBase64String(text));
        }
        catch (Exception e) when (e is CryptographicException or FormatException)
        { throw new InvoiceException("El archivo no es un certificado válido. Subí el .crt que descargaste de AFIP."); }
        using (certificate)
        {
            using var key = LoadKey(row);
            using var publicKey = certificate.GetRSAPublicKey();
            if (publicKey == null || !publicKey.ExportSubjectPublicKeyInfo().AsSpan().SequenceEqual(key.ExportSubjectPublicKeyInfo()))
                throw new InvoiceException("El certificado no corresponde al último pedido (CSR) generado para este ambiente.", 409);
            var billing = await BillingAsync(company);
            if (!certificate.Subject.Contains(billing.Cuit))
                throw new InvoiceException($"El certificado es de otro CUIT ({certificate.Subject}).", 409);
            row.Certificate = certificate.ExportCertificatePem();
            row.CertificateSubject = certificate.Subject;
            row.CertificateExpiresAt = certificate.NotAfter.ToUniversalTime();
            row.CertificateUploadedAt = DateTime.UtcNow;
        }
        await db.AfipTokens.Where(x => x.CompanyId == company && x.Environment == env).ExecuteDeleteAsync();
        await db.SaveChangesAsync();
        return await StatusAsync(company);
    }

    /// Verifica servidores, certificado y punto de venta en el ambiente configurado.
    public async Task<object> TestAsync(int company)
    {
        var billing = await BillingAsync(company);
        var servers = await afip.DummyAsync(billing.Environment);
        var auth = await AuthAsync(company, billing.Environment, billing.Cuit);
        if (billing.PointOfSale is not { } pos) return new { servers, authenticated = true, message = "Conexión correcta. Falta indicar el punto de venta." };
        var type = InvoiceService.EmitterIsResponsableInscripto(billing) ? AfipCodes.FacturaB : AfipCodes.FacturaC;
        var last = await afip.LastAuthorizedAsync(billing.Environment, auth, pos, type);
        return new { servers, authenticated = true, message = $"Conexión correcta. Último {AfipCodes.TypeName(type)} del punto de venta {pos}: {last}." };
    }

    public async Task<AfipAuth> AuthAsync(int company, string env, string cuit, CancellationToken ct = default)
    {
        var cached = await db.AfipTokens.AsNoTracking()
            .SingleOrDefaultAsync(x => x.CompanyId == company && x.Environment == env && x.Service == Service, ct);
        if (cached != null && cached.ExpiresAt > DateTime.UtcNow.AddMinutes(5))
            return new AfipAuth(cached.Token, cached.Sign, long.Parse(cuit));

        var row = await db.AfipCredentials.AsNoTracking().SingleOrDefaultAsync(x => x.CompanyId == company && x.Environment == env, ct);
        if (row?.Certificate == null)
            throw new InvoiceException($"Falta el certificado de AFIP para {(env == "Produccion" ? "producción" : "homologación")}. Configuralo en Configuración › Empresa y facturación.", 409);
        if (row.CertificateExpiresAt < DateTime.UtcNow)
            throw new InvoiceException("El certificado de AFIP venció. Generá uno nuevo en Configuración › Empresa y facturación.", 409);
        using var key = LoadKey(row);
        using var certificate = X509Certificate2.CreateFromPem(row.Certificate);
        var ticket = await afip.LoginAsync(env, certificate, key, Service, ct);
        await db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO afip_tokens (id_empresa, ambiente, servicio, token, sign, vence)
            VALUES ({company}, {env}, {Service}, {ticket.Token}, {ticket.Sign}, {ticket.ExpiresAt})
            ON CONFLICT (id_empresa, ambiente, servicio) DO UPDATE SET token = EXCLUDED.token, sign = EXCLUDED.sign, vence = EXCLUDED.vence", ct);
        return new AfipAuth(ticket.Token, ticket.Sign, long.Parse(cuit));
    }

    public async Task<BillingSettings> BillingAsync(int company)
    {
        var settings = await db.CompanySettings.AsNoTracking().SingleOrDefaultAsync(x => x.CompanyId == company)
            ?? throw new InvoiceException("Completá los datos de facturación en Configuración › Empresa y facturación.", 409);
        return JsonSerializer.Deserialize<BillingSettings>(settings.BillingJson) ?? new BillingSettings();
    }

    // ─── Cifrado de la clave privada (AES-GCM con Afip:CredentialKey) ────────
    private RSA LoadKey(AfipCredential row)
    {
        var rsa = RSA.Create();
        rsa.ImportPkcs8PrivateKey(Decrypt(row.EncryptedKey), out _);
        return rsa;
    }

    private byte[]? EncryptionKey()
    {
        var value = configuration["Afip:CredentialKey"];
        if (string.IsNullOrWhiteSpace(value)) return null;
        try { var key = Convert.FromBase64String(value); return key.Length == 32 ? key : null; }
        catch (FormatException) { return null; }
    }

    private byte[] RequireKey() => EncryptionKey()
        ?? throw new InvoiceException("Falta configurar Afip:CredentialKey (32 bytes en base64) en appsettings.Local.json.", 500);

    private byte[] Encrypt(byte[] plain)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var tag = new byte[16];
        var cipher = new byte[plain.Length];
        using (var aes = new AesGcm(RequireKey(), 16)) aes.Encrypt(nonce, plain, cipher, tag);
        CryptographicOperations.ZeroMemory(plain);
        return [.. nonce, .. tag, .. cipher];
    }

    private byte[] Decrypt(byte[] data)
    {
        var plain = new byte[data.Length - 28];
        try
        {
            using var aes = new AesGcm(RequireKey(), 16);
            aes.Decrypt(data.AsSpan(0, 12), data.AsSpan(28), data.AsSpan(12, 16), plain);
        }
        catch (AuthenticationTagMismatchException)
        { throw new InvoiceException("No se pudo leer la clave del certificado: Afip:CredentialKey cambió. Generá un certificado nuevo.", 500); }
        return plain;
    }

    private static string ValidEnvironment(string env) => env is "Homologacion" or "Produccion"
        ? env : throw new InvoiceException("Ambiente inválido: usá Homologacion o Produccion.");

    private static string Ascii(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormD);
        return new string(normalized.Where(c => c < 128 && !char.IsControl(c)).ToArray()).Trim();
    }
}
