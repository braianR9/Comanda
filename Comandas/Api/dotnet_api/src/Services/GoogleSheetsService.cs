using BarIceCreamShop.Api.Models;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Services;
using Google.Apis.Sheets.v4;
using Google.Apis.Sheets.v4.Data;

namespace BarIceCreamShop.Api.Services;

/// Agrega filas a una planilla de Google Sheets vía cuenta de servicio.
/// Si no hay credenciales configuradas queda deshabilitado (no rompe nada).
public sealed class GoogleSheetsService
{
    private readonly string? _credentialsPath;
    private readonly ILogger<GoogleSheetsService> _logger;
    private readonly SemaphoreSlim _initLock = new(1, 1);
    private SheetsService? _client;

    public GoogleSheetsService(IConfiguration configuration, ILogger<GoogleSheetsService> logger)
    {
        _logger = logger;
        var path = configuration["GoogleSheets:CredentialsPath"];
        _credentialsPath = string.IsNullOrWhiteSpace(path) || !File.Exists(path) ? null : path;
        if (_credentialsPath == null)
            logger.LogWarning("GoogleSheets:CredentialsPath no está configurado; la sincronización queda deshabilitada.");
        else
            ServiceAccountEmail = ReadServiceAccountEmail(_credentialsPath);
    }

    public bool Enabled => _credentialsPath != null;

    /// Email de la cuenta de servicio: cada cliente comparte SU planilla con este
    /// mismo email (la credencial es una sola, compartida por todas las empresas).
    public string? ServiceAccountEmail { get; }

    private static string? ReadServiceAccountEmail(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            using var json = System.Text.Json.JsonDocument.Parse(stream);
            return json.RootElement.TryGetProperty("client_email", out var value) ? value.GetString() : null;
        }
        catch
        {
            return null;
        }
    }

    /// Normaliza tanto un ID crudo como un link completo de Google Sheets al ID.
    public static string? ExtractSheetId(string? sheetIdOrUrl)
    {
        if (string.IsNullOrWhiteSpace(sheetIdOrUrl)) return null;
        var value = sheetIdOrUrl.Trim();
        var match = System.Text.RegularExpressions.Regex.Match(value, @"/d/([a-zA-Z0-9-_]+)");
        return match.Success ? match.Groups[1].Value : value;
    }

    public async Task AppendSaleRowsAsync(string sheetId, IReadOnlyList<SalesDetailLineDto> rows, CancellationToken cancellationToken)
    {
        if (!Enabled) throw new InvalidOperationException("La sincronización con Google Sheets no está configurada.");
        if (rows.Count == 0) return;
        var client = await GetClientAsync(cancellationToken);
        var spreadsheet = await client.Spreadsheets.Get(sheetId).ExecuteAsync(cancellationToken);
        var sheetName = spreadsheet.Sheets?.FirstOrDefault()?.Properties?.Title;
        if (string.IsNullOrWhiteSpace(sheetName))
            throw new InvalidOperationException("La planilla de Google Sheets no contiene ninguna pestaña.");

        var values = rows.Select(row => new List<object?>
        {
            row.Date.ToString("dd/MM/yyyy HH:mm"),
            row.OrderNumber,
            row.ProductCode,
            row.ProductName,
            row.Quantity,
            row.Total,
            row.RealAmount,
            row.RubroNombre,
            row.SubRubroNombre ?? "",
            row.TipoPedido,
            row.SectorNombre ?? "",
        } as IList<object>).ToList();

        var request = client.Spreadsheets.Values.Append(
            new ValueRange { Values = values }, sheetId, $"'{sheetName.Replace("'", "''")}'!A:K");
        request.ValueInputOption = SpreadsheetsResource.ValuesResource.AppendRequest.ValueInputOptionEnum.USERENTERED;
        request.InsertDataOption = SpreadsheetsResource.ValuesResource.AppendRequest.InsertDataOptionEnum.INSERTROWS;
        await request.ExecuteAsync(cancellationToken);
    }

    private async Task<SheetsService> GetClientAsync(CancellationToken cancellationToken)
    {
        if (_client != null) return _client;
        await _initLock.WaitAsync(cancellationToken);
        try
        {
            if (_client != null) return _client;
            var credential = (await CredentialFactory.FromFileAsync<ServiceAccountCredential>(_credentialsPath!, cancellationToken))
                .ToGoogleCredential().CreateScoped(SheetsService.Scope.Spreadsheets);
            _client = new SheetsService(new BaseClientService.Initializer
            {
                HttpClientInitializer = credential,
                ApplicationName = "Foco-Sales-Sync",
            });
            return _client;
        }
        finally
        {
            _initLock.Release();
        }
    }
}
