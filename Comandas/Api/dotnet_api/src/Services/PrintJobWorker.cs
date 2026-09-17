using System.Globalization;
using System.Text;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class PrintJobWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<PrintJobWorker> _logger;

    public PrintJobWorker(
        IServiceScopeFactory scopeFactory,
        IConfiguration configuration,
        ILogger<PrintJobWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _configuration = configuration;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Permite que la API termine de iniciar antes de consultar la cola.
        await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var processed = await ProcessNextAsync(stoppingToken);
                if (!processed)
                    await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al procesar la cola de impresión.");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private async Task<bool> ProcessNextAsync(CancellationToken cancellationToken)
    {
        await using var scope = _scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var configurations = scope.ServiceProvider.GetRequiredService<PrinterConfigurationService>();
        var transport = scope.ServiceProvider.GetRequiredService<PrinterTransport>();

        var job = await db.PrintJobs
            .Where(x => x.Status == "Pendiente")
            .OrderBy(x => x.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (job is null)
            return false;

        job.Status = "Procesando";
        await db.SaveChangesAsync(cancellationToken);

        try
        {
            var sale = await db.Orders
                .AsNoTracking()
                .Include(x => x.Table)
                    .ThenInclude(x => x.Sector)
                .Include(x => x.Items)
                .Include(x => x.Payments)
                .Include(x => x.Commands)
                    .ThenInclude(x => x.Lines)
                .SingleOrDefaultAsync(x => x.Id == job.OrderId, cancellationToken)
                ?? throw new InvalidOperationException($"No existe la venta {job.OrderId}.");

            var printer = job.PrinterConfigurationId.HasValue
                ? await db.PrinterConfigurations.AsNoTracking().SingleOrDefaultAsync(x => x.Id == job.PrinterConfigurationId.Value && x.Activa, cancellationToken)
                : await configurations.ResolveAsync(sale.IdEmpresa, sale.IdSucursal, job.JobType);
            if (printer is null)
            {
                var fallbackQueue = string.IsNullOrWhiteSpace(job.PrinterId) ? _configuration["PrinterSettings:QueueName"] : job.PrinterId;
                if (string.IsNullOrWhiteSpace(fallbackQueue)) throw new InvalidOperationException($"No hay una impresora activa configurada para {job.JobType}.");
                printer = new PrinterConfiguration { Nombre = fallbackQueue, TipoConexion = "Cups", NombreCola = fallbackQueue, Uso = "Ambos", Activa = true };
            }

            var waiterId = sale.Commands
                .OrderByDescending(x => x.Fecha)
                .ThenByDescending(x => x.Id)
                .Select(x => x.MozoId)
                .FirstOrDefault() ?? sale.MozoId;
            var waiterName = "Sin asignar";
            if (waiterId.HasValue)
            {
                waiterName = await db.Usuarios
                    .AsNoTracking()
                    .Where(x => x.Id == waiterId.Value)
                    .Select(x => (x.Nombre + " " + x.Apellido).Trim())
                    .SingleOrDefaultAsync(cancellationToken) ?? "Sin asignar";
            }

            byte[] ticket;
            if (job.JobType == "TicketVenta")
            {
                var companyName = await db.Empresas.AsNoTracking()
                    .Where(x => x.Id == sale.IdEmpresa)
                    .Select(x => x.Nombre)
                    .SingleAsync(cancellationToken);
                var branch = await db.Sucursales.AsNoTracking()
                    .Where(x => x.Id == sale.IdSucursal)
                    .Select(x => new { x.Nombre, x.Direccion, x.Telefono })
                    .SingleAsync(cancellationToken);
                ticket = BuildSaleTicket(sale, companyName, branch.Nombre, branch.Direccion, branch.Telefono, waiterName);
            }
            else
            {
                ticket = BuildCommandTicket(sale, waiterName);
            }
            await transport.SendAsync(printer, ticket, cancellationToken);

            job.Status = "Impreso";
            if (printer.Id > 0) job.PrinterConfigurationId = printer.Id;
            job.PrinterId = printer.NombreCola ?? printer.Nombre;
            await db.SaveChangesAsync(cancellationToken);
            _logger.LogInformation("Trabajo {PrintJobId} enviado a {PrinterName}.", job.Id, printer.Nombre);
        }
        catch (Exception ex)
        {
            job.Status = "Error";
            await db.SaveChangesAsync(cancellationToken);
            _logger.LogError(ex, "No se pudo imprimir el trabajo {PrintJobId}.", job.Id);
        }

        return true;
    }

    private static byte[] BuildCommandTicket(Order sale, string waiterName)
    {
        const int width = 42;
        var command = sale.Commands.OrderByDescending(x => x.Fecha).ThenByDescending(x => x.Id).FirstOrDefault();
        var text = new StringBuilder();

        text.Append("\u001b!\u0008");
        text.AppendLine(Center("COMANDA", width));
        text.Append("\u001b!\u0008");
        var tableName = sale.Table?.Nombre ?? sale.TableId.ToString(CultureInfo.InvariantCulture);
        var sectorName = sale.Table?.Sector?.Nombre;
        var tableHeading = tableName.StartsWith("Mesa", StringComparison.OrdinalIgnoreCase)
            ? tableName.ToUpperInvariant() : $"MESA {tableName}";
        const string tableLabel = "Mesa: ";
        text.Append(tableLabel);
        // La mesa se destaca con doble altura y conserva el ancho normal.
        AppendCommandText(text, tableHeading, width - tableLabel.Length, "\u001b!\u0018");
        if (!string.IsNullOrWhiteSpace(sectorName))
            AppendCommandText(text, $"Sector: {sectorName}", width);
        AppendCommandText(text, $"Pedido Nro: {sale.PrintedNumber}", width);
        if (command is not null)
        {
            text.Append("\u001ba\u0001");
            AppendCommandText(text, sale.Estado == "Cancelada" ? "ANULACIÓN DEL PEDIDO" : command.Tipo.ToUpperInvariant(), width, "\u001b!\u0018");
            text.Append("\u001ba\u0000");
        }
        text.AppendLine(new string('=', width));
        text.AppendLine($"Fecha: {(command?.Fecha ?? DateTime.UtcNow).ToLocalTime():dd/MM/yyyy HH:mm}");
        AppendCommandText(text, $"Mozo: {waiterName}", width);
        text.AppendLine(new string('-', width));
        text.AppendLine($"{"Cant.",-7}Descripcion");
        text.AppendLine(new string('-', width));

        if (command is not null)
        {
            foreach (var line in command.Lines.OrderBy(x => x.Id))
            {
                var quantity = line.QuantityDelta;
                var action = quantity < 0 ? "-"
                    : quantity > 0 && command.Tipo != "Inicial" ? "+" : string.Empty;
                AppendCommandItem(text, action, Math.Abs(quantity), line.ProductName, line.Comment, width);
            }
        }
        else
        {
            foreach (var item in sale.Items.Where(x => x.Estado == "Activo").OrderBy(x => x.Id))
                AppendCommandItem(text, string.Empty, item.Quantity, item.ProductName, item.Comment, width);
        }

        text.AppendLine(new string('=', width));
        text.AppendLine();
        text.AppendLine();
        text.AppendLine();

        return ToEscPos(text.ToString());
    }

    private static void AppendCommandItem(
        StringBuilder text, string action, decimal quantity, string productName, string? comment, int width)
    {
        const int quantityWidth = 7;
        var quantityText = $"{action}{FormatQuantity(quantity)}";
        var descriptionLines = Wrap(productName, width - quantityWidth);
        // Mantiene alineada la descripción cuando ocupa más de una línea.
        text.AppendLine($"{quantityText,-quantityWidth}{descriptionLines[0]}");
        foreach (var continuation in descriptionLines.Skip(1))
            text.AppendLine($"{string.Empty,-quantityWidth}{continuation}");
        if (!string.IsNullOrWhiteSpace(comment))
        {
            AppendCommandText(text, $">> OBS: {comment}", width);
        }
        text.AppendLine();
        text.AppendLine(new string('-', width));
    }

    private static void AppendCommandText(
        StringBuilder text, string value, int width, string font = "\u001b!\u0008")
    {
        text.Append(font);
        foreach (var line in Wrap(value, width))
            text.AppendLine(line);
        text.Append("\u001b!\u0008");
    }

    private static byte[] BuildSaleTicket(
        Order sale,
        string companyName,
        string branchName,
        string? address,
        string? phone,
        string waiterName)
    {
        const int width = 42;
        var text = new StringBuilder();
        // Fuente A enfatizada a tamaño normal para una lectura compacta y firme.
        text.Append("\u001b!\u0008");
        var closedAt = (sale.FechaCierre ?? DateTime.UtcNow).ToLocalTime();
        var tableName = sale.Table?.Nombre ?? sale.TableId.ToString(CultureInfo.InvariantCulture);
        var sectorName = sale.Table?.Sector?.Nombre;
        var tableDescription = string.IsNullOrWhiteSpace(sectorName)
            ? tableName
            : $"{tableName} ({sectorName})";

        text.AppendLine(Center(companyName.ToUpperInvariant(), width));
        if (!string.IsNullOrWhiteSpace(branchName) && !string.Equals(branchName, companyName, StringComparison.OrdinalIgnoreCase))
            text.AppendLine(Center(branchName, width));
        if (!string.IsNullOrWhiteSpace(address))
            text.AppendLine(Center(address, width));
        if (!string.IsNullOrWhiteSpace(phone))
            text.AppendLine(Center($"Tel: {phone}", width));
        text.AppendLine();
        text.AppendLine($"Pedido Nro: {sale.PrintedNumber}");
        text.AppendLine($"FECHA: {closedAt:dd-MM-yyyy}  HORA: {closedAt:HH:mm} hs");
        text.AppendLine(new string('.', width));
        text.AppendLine($"MESA: {tableDescription}");
        text.AppendLine($"MOZO: {waiterName}");
        text.AppendLine(new string('.', width));
        text.AppendLine($"{"CANT.",-6}{"DESCRIPCION",-23}{"PRECIO",13}");
        text.AppendLine(new string('-', width));

        var activeItems = sale.Items.Where(x => x.Estado == "Activo").OrderBy(x => x.Id).ToList();
        foreach (var item in activeItems)
        {
            var descriptionLines = Wrap(item.ProductName, 23);
            var quantity = $"{FormatQuantity(item.Quantity)}x";
            text.AppendLine($"{quantity,-6}{descriptionLines[0],-23}{FormatMoney(item.Subtotal),13}");
            foreach (var continuation in descriptionLines.Skip(1))
                text.AppendLine($"{"",-6}{continuation}");
        }

        text.AppendLine();
        text.AppendLine($"Cant. de Items: {FormatQuantity(activeItems.Sum(x => x.Quantity))}");
        text.AppendLine(new string('.', width));
        if (sale.ImporteDescuento > 0)
            text.AppendLine($"DESCUENTO:{FormatMoney(sale.ImporteDescuento),32}");
        foreach (var payment in sale.Payments.Where(p => p.AdjustmentAmount != 0))
        {
            var label = $"{(payment.AdjustmentAmount > 0 ? "RECARGO" : "DESC. PAGO")} {payment.PaymentTypeName} {payment.Percentage:0.##}%";
            foreach (var line in Wrap(label, width)) text.AppendLine(line);
            text.AppendLine(FormatMoney(payment.AdjustmentAmount).PadLeft(width));
        }
        text.AppendLine($"TOTAL:{FormatMoney(sale.Total),36}");
        var paymentNames = string.Join(" + ", sale.Payments.Select(x => x.PaymentTypeName).Distinct());
        foreach (var line in Wrap($"FORMA DE PAGO: {(string.IsNullOrWhiteSpace(paymentNames) ? "Sin informar" : paymentNames)}", width))
            text.AppendLine(line);
        foreach (var payment in sale.Payments)
        {
            foreach (var line in Wrap(payment.PaymentTypeName, width)) text.AppendLine(line);
            text.AppendLine(FormatMoney(payment.Amount).PadLeft(width));
        }
        text.AppendLine();
        text.AppendLine(Center("NO VALIDO COMO FACTURA", width));
        text.AppendLine();
        text.AppendLine();
        text.AppendLine();
        return ToEscPos(text.ToString());
    }

    private static byte[] ToEscPos(string text)
    {
        // La impresora soporta ESC/POS. Se normaliza a ASCII para evitar caracteres
        // corruptos hasta configurar explícitamente la página de códigos del equipo.
        var printableText = RemoveDiacritics(text);
        var body = Encoding.ASCII.GetBytes(printableText);
        byte[] initialize = [0x1B, 0x40];
        // ESC ! 0x08: fuente A enfatizada, con proporciones normales y trazos
        // más firmes para mejorar la lectura en papel térmico.
        byte[] readableFont = [0x1B, 0x21, 0x08];
        byte[] normalFont = [0x1B, 0x21, 0x00];
        // Avanza cinco líneas físicas antes de accionar el cutter para que la
        // última leyenda no quede dentro de la zona de corte.
        byte[] feedBeforeCut = [0x1B, 0x64, 0x05];
        byte[] cut = [0x1D, 0x56, 0x00];
        return [.. initialize, .. readableFont, .. body, .. normalFont, .. feedBeforeCut, .. cut];
    }

    private static string FormatQuantity(decimal value)
        => value % 1 == 0
            ? value.ToString("0", CultureInfo.InvariantCulture)
            : value.ToString("0.###", CultureInfo.InvariantCulture);

    private static string FormatMoney(decimal value)
        => "$ " + value.ToString("N2", CultureInfo.GetCultureInfo("es-AR"));

    private static List<string> Wrap(string value, int width)
    {
        var result = new List<string>();
        var remaining = value.Trim();
        while (remaining.Length > width)
        {
            var cut = remaining.LastIndexOf(' ', width);
            if (cut <= 0) cut = width;
            result.Add(remaining[..cut].Trim());
            remaining = remaining[cut..].TrimStart();
        }
        result.Add(remaining);
        return result;
    }

    private static string Center(string value, int width)
        => value.Length >= width ? value : value.PadLeft(value.Length + (width - value.Length) / 2);

    private static string RemoveDiacritics(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormD);
        var result = new StringBuilder(normalized.Length);
        foreach (var character in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
                result.Append(character);
        }
        return result.ToString().Normalize(NormalizationForm.FormC);
    }
}
