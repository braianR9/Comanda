using System.Diagnostics;
using System.Net.Sockets;
using System.Text;
using BarIceCreamShop.Api.Models;

namespace BarIceCreamShop.Api.Services;

public sealed class PrinterTransport
{
    public async Task SendAsync(PrinterConfiguration printer, byte[] content, CancellationToken cancellationToken = default)
    {
        if (printer.TipoConexion == "Cups")
        {
            if (string.IsNullOrWhiteSpace(printer.NombreCola)) throw new InvalidOperationException("La impresora no tiene una cola CUPS configurada.");
            await SendToCupsAsync(printer.NombreCola, content, cancellationToken);
            return;
        }
        if (printer.TipoConexion == "Red")
        {
            if (string.IsNullOrWhiteSpace(printer.DireccionIp) || !printer.Puerto.HasValue) throw new InvalidOperationException("La impresora de red no tiene IP y puerto configurados.");
            using var client = new TcpClient();
            await client.ConnectAsync(printer.DireccionIp, printer.Puerto.Value, cancellationToken);
            await using var stream = client.GetStream();
            await stream.WriteAsync(content, cancellationToken);
            await stream.FlushAsync(cancellationToken);
            return;
        }
        throw new InvalidOperationException("Tipo de conexión de impresora no soportado.");
    }

    public Task TestAsync(PrinterConfiguration printer, CancellationToken cancellationToken = default)
    {
        var text = Encoding.ASCII.GetBytes($"\u001b@\u001b!\bPRUEBA DE IMPRESION\n{RemoveDiacritics(printer.Nombre)}\nConexion correcta\n\n\n\u001bd\u0005\u001dV\0");
        return SendAsync(printer, text, cancellationToken);
    }

    private static async Task SendToCupsAsync(string queueName, byte[] content, CancellationToken cancellationToken)
    {
        var info = new ProcessStartInfo { FileName = "/usr/bin/lp", RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        info.ArgumentList.Add("-d"); info.ArgumentList.Add(queueName); info.ArgumentList.Add("-o"); info.ArgumentList.Add("raw");
        using var process = Process.Start(info) ?? throw new InvalidOperationException("No se pudo iniciar el comando lp.");
        await process.StandardInput.BaseStream.WriteAsync(content, cancellationToken);
        process.StandardInput.Close();
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var error = await errorTask;
        if (process.ExitCode != 0) throw new InvalidOperationException($"CUPS rechazó la impresión: {error.Trim()}");
    }

    private static string RemoveDiacritics(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormD);
        return new string(normalized.Where(c => System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.NonSpacingMark).ToArray()).Normalize(NormalizationForm.FormC);
    }
}
