using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;

// Configuración junto al ejecutable: { "apiUrl": "https://api.focobr.net", "clave": "foco_..." }
var configPath = Path.Combine(AppContext.BaseDirectory, "agente.json");
if (!File.Exists(configPath))
{
    Log($"No encuentro {configPath}. Volvé a correr el instalador.");
    return 1;
}
var config = JsonSerializer.Deserialize(File.ReadAllText(configPath), AgentJson.Default.AgentConfig);
if (config is null || string.IsNullOrWhiteSpace(config.ApiUrl) || string.IsNullOrWhiteSpace(config.Clave))
{
    Log("Falta la dirección de la API o la clave en agente.json. Volvé a correr el instalador.");
    return 1;
}

using var http = new HttpClient { BaseAddress = new Uri(config.ApiUrl.TrimEnd('/') + "/"), Timeout = TimeSpan.FromSeconds(30) };
http.DefaultRequestHeaders.Add("X-Agente-Clave", config.Clave.Trim());
http.DefaultRequestHeaders.Add("X-Agente-Equipo", $"{Environment.MachineName} ({(OperatingSystem.IsWindows() ? "Windows" : "Mac")})");
var transport = new PrinterTransport();
using var stop = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Cancel(); };

Log($"Agente iniciado. API: {config.ApiUrl}");
var lastProblem = "";
while (!stop.IsCancellationRequested)
{
    try
    {
        using var response = await http.PostAsync("api/print-agent/next", null, stop.Token);
        if (response.StatusCode == HttpStatusCode.Unauthorized)
        {
            Problem("La clave del agente no es válida. Generá una nueva en Impresoras y volvé a instalar.");
            await Task.Delay(TimeSpan.FromSeconds(30), stop.Token);
            continue;
        }
        response.EnsureSuccessStatusCode();
        var job = (await response.Content.ReadFromJsonAsync(AgentJson.Default.JobResponse, stop.Token))?.Data;
        if (lastProblem != "") { Log("Conexión con la API restablecida."); lastProblem = ""; }
        if (job is null)
        {
            await Task.Delay(TimeSpan.FromSeconds(2), stop.Token);
            continue;
        }

        var result = new JobResult { Ok = true };
        try
        {
            var printer = new PrinterConfiguration
            {
                Nombre = job.Printer.Name, TipoConexion = job.Printer.ConnectionType,
                NombreCola = job.Printer.QueueName, DireccionIp = job.Printer.IpAddress, Puerto = job.Printer.Port,
            };
            await transport.SendAsync(printer, Convert.FromBase64String(job.Content), stop.Token);
            Log($"Trabajo {job.Id} ({job.Type}) impreso en {job.Printer.Name}.");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            result = new JobResult { Ok = false, Error = ex.Message };
            Log($"No se pudo imprimir el trabajo {job.Id} en {job.Printer.Name}: {ex.Message}");
        }
        using var ack = await http.PostAsJsonAsync($"api/print-agent/jobs/{job.Id}/result", result, AgentJson.Default.JobResult, stop.Token);
    }
    catch (OperationCanceledException) when (stop.IsCancellationRequested)
    {
        break;
    }
    catch (Exception ex)
    {
        Problem($"Sin conexión con la API: {ex.Message}");
        await Task.Delay(TimeSpan.FromSeconds(10), stop.Token).ContinueWith(_ => { });
    }
}
Log("Agente detenido.");
return 0;

// Los errores repetidos se registran una sola vez para no llenar el log.
void Problem(string message)
{
    if (message == lastProblem) return;
    lastProblem = message;
    Log(message);
}

static void Log(string message) => Console.WriteLine($"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}");

sealed class AgentConfig
{
    public string ApiUrl { get; set; } = "";
    public string Clave { get; set; } = "";
}

sealed class JobResponse { public AgentJob? Data { get; set; } }

sealed class AgentJob
{
    public int Id { get; set; }
    public string Type { get; set; } = "";
    public AgentPrinter Printer { get; set; } = new();
    public string Content { get; set; } = "";
}

sealed class AgentPrinter
{
    public string Name { get; set; } = "";
    public string ConnectionType { get; set; } = "";
    public string? QueueName { get; set; }
    public string? IpAddress { get; set; }
    public int? Port { get; set; }
}

sealed class JobResult
{
    public bool Ok { get; set; }
    public string? Error { get; set; }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true)]
[JsonSerializable(typeof(AgentConfig))]
[JsonSerializable(typeof(JobResponse))]
[JsonSerializable(typeof(JobResult))]
partial class AgentJson : JsonSerializerContext;
