using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

/// Cadena de conexión local para las pruebas: appsettings.Local.json (no versionado)
/// o la variable ConnectionStrings__DefaultConnection.
static class TestConfig
{
    public static string ConnectionString(string apiRoot = "../../../Api/dotnet_api")
    {
        var fromEnv = Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection");
        if (!string.IsNullOrWhiteSpace(fromEnv)) return fromEnv;
        var path = Path.Combine(apiRoot, "src/appsettings.Local.json");
        if (!File.Exists(path))
            throw new Exception($"No existe {path}. Copiá appsettings.Local.example.json y completalo.");
        using var config = JsonDocument.Parse(File.ReadAllText(path));
        return config.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
    }

    /// Facturación sin AFIP: sin datos fiscales, la facturación automática no se dispara.
    public static InvoiceService Invoices(AppDbContext db, IConfiguration configuration)
    {
        var afip = new AfipClient(new HttpClient(), NullLogger<AfipClient>.Instance);
        return new InvoiceService(db, afip, new AfipCredentialService(db, afip, configuration), configuration, NullLogger<InvoiceService>.Instance);
    }
}
