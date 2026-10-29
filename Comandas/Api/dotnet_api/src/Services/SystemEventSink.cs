using System.Security.Claims;
using System.Text.RegularExpressions;
using System.Threading.Channels;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class SystemEventSink(IConfiguration config, IHttpContextAccessor accessor)
{
    public static AsyncLocal<bool> Writing { get; } = new();
    public Channel<SystemEvent> Queue { get; } = Channel.CreateBounded<SystemEvent>(new BoundedChannelOptions(1000)
        { FullMode = BoundedChannelFullMode.Wait, SingleReader = true });

    public string Redact(string? value)
    {
        var text = value ?? "";
        foreach (var pair in config.AsEnumerable().Where(x => x.Value?.Length >= 6 &&
            (Regex.IsMatch(x.Key, "(password(hash)?|secret|token|key|connection)(:value)?$", RegexOptions.IgnoreCase) || x.Key.StartsWith("ConnectionStrings:"))))
            text = text.Replace(pair.Value!, "[oculto]", StringComparison.Ordinal);
        text = Regex.Replace(text, @"(?i)(password|pwd|token|secret|authorization|api[-_]?key|focoKey)\s*[:=]\s*[^;\s,]+", "$1=[oculto]");
        text = Regex.Replace(text, @"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[token oculto]");
        return text.Length <= 16000 ? text : text[..16000];
    }

    public void Error(string source, string message, Exception? exception = null, int? status = null)
    {
        var context = accessor.HttpContext;
        var item = new SystemEvent { Source = source.Length > 200 ? source[..200] : source,
            Message = Redact(message), Detail = exception == null ? null : Redact(exception.GetType().FullName + ": " + exception.Message + "\n" + exception.StackTrace),
            CompanyId = Id("id_empresa"), BranchId = Id("id_sucursal"), UserId = Id(ClaimTypes.NameIdentifier),
            Method = context?.Request.Method, Path = context?.Request.Path.Value,
            TraceId = context?.TraceIdentifier, StatusCode = status };
        if (!Queue.Writer.TryWrite(item)) WriteFallback(item);
        int? Id(string name) => int.TryParse(context?.User.FindFirstValue(name), out var id) ? id : null;
    }

    private readonly object _fileLock = new();
    public void WriteFallback(SystemEvent item)
    {
        try
        {
            lock (_fileLock)
            {
                var directory = Path.Combine(Directory.GetCurrentDirectory(), "logs");
                Directory.CreateDirectory(directory);
                var path = Path.Combine(directory, $"systems-fallback-{DateTime.UtcNow:yyyy-MM-dd}.jsonl");
                var options = new FileStreamOptions { Mode = FileMode.Append, Access = FileAccess.Write };
                if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
                using var stream = new FileStream(path, options);
                using var writer = new StreamWriter(stream);
                writer.WriteLine(System.Text.Json.JsonSerializer.Serialize(item));
            }
        }
        catch { Console.Error.WriteLine("No se pudo persistir un evento de sistemas. Revisá la base y el directorio logs."); }
    }
}

public sealed class SystemEventWorker(SystemEventSink sink, IServiceScopeFactory scopes) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await foreach (var item in sink.Queue.Reader.ReadAllAsync(stoppingToken))
            {
                try
                {
                    SystemEventSink.Writing.Value = true;
                    using var scope = scopes.CreateScope();
                    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    db.SystemEvents.Add(item);
                    await db.SaveChangesAsync(stoppingToken);
                }
                catch { sink.WriteFallback(item); }
                finally { SystemEventSink.Writing.Value = false; }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        finally { while (sink.Queue.Reader.TryRead(out var item)) sink.WriteFallback(item); }
    }
}

public sealed class SystemErrorLoggerProvider(SystemEventSink sink) : ILoggerProvider
{
    public ILogger CreateLogger(string categoryName) => new ErrorLogger(sink, categoryName);
    public void Dispose() { }
    private sealed class ErrorLogger(SystemEventSink sink, string category) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel level) => level >= LogLevel.Error &&
            !SystemEventSink.Writing.Value &&
            !category.StartsWith("Microsoft.EntityFrameworkCore", StringComparison.Ordinal);
        public void Log<TState>(LogLevel level, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (IsEnabled(level)) sink.Error(category, formatter(state, exception), exception);
        }
    }
}
