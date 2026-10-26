using System.Globalization;
using System.Text;
using System.Text.Json;
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
            byte[] ticket;
            int companyId, branchId;

            if (job.CajaId.HasValue)
            {
                var caja = await db.Cajas.AsNoTracking()
                    .Include(x => x.UsuarioApertura)
                    .Include(x => x.UsuarioCierre)
                    .SingleOrDefaultAsync(x => x.Id == job.CajaId.Value, cancellationToken)
                    ?? throw new InvalidOperationException($"No existe la caja {job.CajaId}.");
                companyId = caja.IdEmpresa; branchId = caja.IdSucursal;
                var detalle = await db.CajaCierreDetalles.AsNoTracking()
                    .Where(x => x.CajaId == caja.Id).OrderByDescending(x => x.Total).ToListAsync(cancellationToken);
                var movimientos = await db.CajaMovimientos.AsNoTracking()
                    .Include(x => x.Usuario)
                    .Where(x => x.CajaId == caja.Id).OrderBy(x => x.Fecha).ToListAsync(cancellationToken);
                var companyName = await db.Empresas.AsNoTracking().Where(x => x.Id == companyId).Select(x => x.Nombre).SingleAsync(cancellationToken);
                var branch = await db.Sucursales.AsNoTracking().Where(x => x.Id == branchId).Select(x => x.Nombre).SingleAsync(cancellationToken);
                ticket = BuildCajaTicket(caja, detalle, movimientos, companyName, branch);
            }
            else
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
                companyId = sale.IdEmpresa; branchId = sale.IdSucursal;

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
                    // Factura vigente de la venta (si la tiene): el ticket sale como comprobante fiscal.
                    // Si el trabajo indica el comprobante (factura, nota de crédito o reimpresión), se imprime ese.
                    var invoice = job.InvoiceId.HasValue
                        ? await db.Invoices.AsNoTracking()
                            .SingleOrDefaultAsync(x => x.Id == job.InvoiceId && x.Status == "Autorizado", cancellationToken)
                        : await db.Invoices.AsNoTracking()
                            .Where(x => x.OrderId == sale.Id && x.Status == "Autorizado" && x.CreditNoteId == null
                                && (x.Type == AfipCodes.FacturaA || x.Type == AfipCodes.FacturaB || x.Type == AfipCodes.FacturaC))
                            .OrderByDescending(x => x.Id).FirstOrDefaultAsync(cancellationToken);
                    if (invoice?.AssociatedInvoiceId is { } associatedId)
                    {
                        var associated = await db.Invoices.AsNoTracking().SingleAsync(x => x.Id == associatedId, cancellationToken);
                        invoice.AssociatedLabel = $"{AfipCodes.TypeName(associated.Type)} {InvoiceService.Format(associated)}";
                    }
                    BillingSettings? billing = null;
                    if (invoice != null)
                    {
                        var json = await db.CompanySettings.AsNoTracking().Where(x => x.CompanyId == sale.IdEmpresa)
                            .Select(x => x.BillingJson).SingleOrDefaultAsync(cancellationToken);
                        billing = json == null ? null : JsonSerializer.Deserialize<BillingSettings>(json);
                    }
                    ticket = BuildSaleTicket(sale, companyName, branch.Nombre, branch.Direccion, branch.Telefono, waiterName,
                        billing == null ? null : invoice, billing, job.Reprint);
                }
                else
                {
                    ticket = BuildCommandTicket(sale, waiterName);
                }
            }

            var printer = job.PrinterConfigurationId.HasValue
                ? await db.PrinterConfigurations.AsNoTracking().SingleOrDefaultAsync(x => x.Id == job.PrinterConfigurationId.Value && x.Activa, cancellationToken)
                : await configurations.ResolveAsync(companyId, branchId, job.JobType == "CierreCaja" ? "TicketVenta" : job.JobType);
            if (printer is null)
            {
                var fallbackQueue = string.IsNullOrWhiteSpace(job.PrinterId) ? _configuration["PrinterSettings:QueueName"] : job.PrinterId;
                if (string.IsNullOrWhiteSpace(fallbackQueue)) throw new InvalidOperationException($"No hay una impresora activa configurada para {job.JobType}.");
                printer = new PrinterConfiguration { Nombre = fallbackQueue, TipoConexion = "Cups", NombreCola = fallbackQueue, Uso = "Ambos", Activa = true };
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
        string waiterName,
        Invoice? invoice = null,
        BillingSettings? billing = null,
        bool reprint = false)
    {
        const int width = 42;
        var text = new StringBuilder();
        // Fuente A enfatizada a tamaño normal para una lectura compacta y firme.
        text.Append("\u001b!\u0008");
        if (invoice != null && billing != null)
        {
            AppendFiscalHeader(text, invoice, billing, width, reprint);
            companyName = "";
        }
        var closedAt = (sale.FechaCierre ?? DateTime.UtcNow).ToLocalTime();
        var tableName = sale.Table?.Nombre ?? sale.TableId.ToString(CultureInfo.InvariantCulture);
        var sectorName = sale.Table?.Sector?.Nombre;
        var tableDescription = string.IsNullOrWhiteSpace(sectorName)
            ? tableName
            : $"{tableName} ({sectorName})";

        if (!string.IsNullOrWhiteSpace(companyName))
            text.AppendLine(Center(companyName.ToUpperInvariant(), width));
        if (invoice == null && !string.IsNullOrWhiteSpace(branchName) && !string.Equals(branchName, companyName, StringComparison.OrdinalIgnoreCase))
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
        if (invoice != null && billing != null)
        {
            AppendFiscalFooter(text, invoice, width);
            var qr = InvoiceService.QrUrl(invoice, billing.Cuit);
            return ToEscPos(text.ToString(), qr == null ? null : QrCode(qr));
        }
        text.AppendLine(Center("NO VALIDO COMO FACTURA", width));
        text.AppendLine();
        text.AppendLine();
        text.AppendLine();
        return ToEscPos(text.ToString());
    }

    private static void AppendFiscalHeader(StringBuilder text, Invoice invoice, BillingSettings billing, int width, bool reprint)
    {
        foreach (var line in Wrap(billing.LegalName.ToUpperInvariant(), width)) text.AppendLine(Center(line, width));
        foreach (var line in Wrap(billing.FiscalAddress, width)) if (line.Length > 0) text.AppendLine(Center(line, width));
        var city = string.Join(" - ", new[] { billing.City, billing.Province }.Where(x => !string.IsNullOrWhiteSpace(x)));
        if (city.Length > 0) text.AppendLine(Center(city, width));
        text.AppendLine($"CUIT: {FormatCuit(billing.Cuit)}");
        if (!string.IsNullOrWhiteSpace(billing.GrossIncomeRegistration)) text.AppendLine($"IIBB: {billing.GrossIncomeRegistration}");
        if (billing.ActivityStart is { } start) text.AppendLine($"Inicio de actividades: {start:dd/MM/yyyy}");
        foreach (var line in Wrap($"IVA {billing.TaxCondition.ToUpperInvariant()}", width)) text.AppendLine(line);
        text.AppendLine(new string('=', width));
        text.AppendLine(Center($"{AfipCodes.TypeName(invoice.Type).ToUpperInvariant()}  (Cod. {invoice.Type:000})", width));
        text.AppendLine($"Nro: {InvoiceService.Format(invoice)}   Fecha: {invoice.Date:dd/MM/yyyy}");
        if (reprint) text.AppendLine(Center("*** REIMPRESION ***", width));
        if (invoice.AssociatedLabel != null) text.AppendLine($"Anula: {invoice.AssociatedLabel}");
        text.AppendLine(new string('-', width));
        if (invoice.DocType == AfipCodes.DocSinIdentificar)
            text.AppendLine("A CONSUMIDOR FINAL");
        else
        {
            foreach (var line in Wrap($"Cliente: {invoice.ReceiverName}", width)) text.AppendLine(line);
            text.AppendLine($"{DocName(invoice.DocType)}: {(invoice.DocType == AfipCodes.DocCuit ? FormatCuit(invoice.DocNumber.ToString(CultureInfo.InvariantCulture)) : invoice.DocNumber.ToString(CultureInfo.InvariantCulture))}");
            text.AppendLine($"IVA: {VatConditionName(invoice.ReceiverVatCondition)}");
        }
        text.AppendLine(new string('=', width));
    }

    private static void AppendFiscalFooter(StringBuilder text, Invoice invoice, int width)
    {
        var vat = JsonSerializer.Deserialize<List<InvoiceVat>>(invoice.VatJson, new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? [];
        if (AfipCodes.Letter(invoice.Type) == "A")
        {
            text.AppendLine($"{"NETO GRAVADO:",-20}{FormatMoney(invoice.Net),22}");
            foreach (var item in vat) text.AppendLine($"{$"IVA {item.Rate:0.##}%:",-20}{FormatMoney(item.Amount),22}");
        }
        else if (AfipCodes.Letter(invoice.Type) == "B")
        {
            text.AppendLine("Regimen de Transparencia Fiscal al");
            text.AppendLine("Consumidor (Ley 27.743)");
            text.AppendLine($"{"IVA contenido:",-20}{FormatMoney(invoice.Vat),22}");
        }
        if (invoice.IsCreditNote && !string.IsNullOrWhiteSpace(invoice.Reason))
            foreach (var line in Wrap($"Motivo: {invoice.Reason}", width)) text.AppendLine(line);
        text.AppendLine(new string('.', width));
        text.AppendLine($"CAE: {invoice.Cae}");
        text.AppendLine($"Vto. CAE: {invoice.CaeExpiresAt:dd/MM/yyyy}");
        if (invoice.Environment != "Produccion") text.AppendLine(Center("*** HOMOLOGACION - SIN VALIDEZ ***", width));
        text.AppendLine(Center("Comprobante autorizado por ARCA", width));
    }

    private static string DocName(int docType) => docType switch
    {
        AfipCodes.DocCuit => "CUIT", AfipCodes.DocCuil => "CUIL", AfipCodes.DocCdi => "CDI",
        AfipCodes.DocPasaporte => "Pasaporte", _ => "DNI",
    };

    private static string VatConditionName(int condition) => condition switch
    {
        AfipCodes.CondResponsableInscripto => "Responsable Inscripto", AfipCodes.CondMonotributo => "Responsable Monotributo",
        AfipCodes.CondExento => "Exento", AfipCodes.CondConsumidorFinal => "Consumidor Final", _ => "No categorizado",
    };

    private static string FormatCuit(string cuit) => cuit.Length == 11 ? $"{cuit[..2]}-{cuit[2..10]}-{cuit[10]}" : cuit;

    /// QR nativo ESC/POS (GS ( k), centrado.
    private static byte[] QrCode(string data)
    {
        var bytes = Encoding.ASCII.GetBytes(data);
        var length = bytes.Length + 3;
        byte[] center = [0x1B, 0x61, 0x01];
        byte[] model = [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00];
        byte[] size = [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04];
        byte[] correction = [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30];
        byte[] store = [0x1D, 0x28, 0x6B, (byte)(length % 256), (byte)(length / 256), 0x31, 0x50, 0x30];
        byte[] print = [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30];
        byte[] left = [0x1B, 0x61, 0x00, 0x0A];
        return [.. center, .. model, .. size, .. correction, .. store, .. bytes, .. print, .. left];
    }

    private static byte[] BuildCajaTicket(
        Caja caja,
        List<CajaCierreDetalle> detalle,
        List<CajaMovimiento> movimientos,
        string companyName,
        string branchName)
    {
        const int width = 42;
        var text = new StringBuilder();
        text.Append("\u001b!\u0008");

        text.AppendLine(Center(companyName.ToUpperInvariant(), width));
        if (!string.IsNullOrWhiteSpace(branchName) && !string.Equals(branchName, companyName, StringComparison.OrdinalIgnoreCase))
            text.AppendLine(Center(branchName, width));
        text.AppendLine();
        text.AppendLine(Center(caja.Estado == "Cerrada" ? "CIERRE DE CAJA" : "REPORTE DE CAJA (ABIERTA)", width));
        text.AppendLine(new string('=', width));

        text.AppendLine($"Abrió: {caja.UsuarioApertura.Nombre} {caja.UsuarioApertura.Apellido}".Trim());
        text.AppendLine($"Fecha apertura: {caja.FechaApertura.ToLocalTime():dd/MM/yyyy HH:mm}");
        if (caja.UsuarioCierre is not null && caja.FechaCierre.HasValue)
        {
            text.AppendLine($"Cerró: {caja.UsuarioCierre.Nombre} {caja.UsuarioCierre.Apellido}".Trim());
            text.AppendLine($"Fecha cierre: {caja.FechaCierre.Value.ToLocalTime():dd/MM/yyyy HH:mm}");
        }
        text.AppendLine(new string('-', width));
        text.AppendLine($"{"Monto inicial:",-28}{FormatMoney(caja.MontoInicial),14}");

        if (detalle.Count > 0)
        {
            text.AppendLine(new string('-', width));
            foreach (var line in Wrap("Cobros por medio de pago:", width)) text.AppendLine(line);
            foreach (var item in detalle)
                text.AppendLine($"{item.MedioPago,-28}{FormatMoney(item.Total),14}");
        }
        text.AppendLine(new string('-', width));
        text.AppendLine($"{"Total vendido:",-28}{FormatMoney(caja.TotalVentas ?? 0),14}");

        var ingresos = movimientos.Where(x => x.Tipo == "Ingreso").ToList();
        var egresos = movimientos.Where(x => x.Tipo == "Egreso").ToList();
        if (ingresos.Count > 0 || egresos.Count > 0)
        {
            text.AppendLine(new string('-', width));
            foreach (var line in Wrap("Movimientos manuales:", width)) text.AppendLine(line);
            foreach (var item in ingresos)
                foreach (var line in Wrap($"+ {item.Motivo} ({item.Usuario.Nombre} {item.Usuario.Apellido})".Trim(), width - 14))
                    text.AppendLine($"{line,-28}{FormatMoney(item.Monto),14}");
            foreach (var item in egresos)
                foreach (var line in Wrap($"- {item.Motivo} ({item.Usuario.Nombre} {item.Usuario.Apellido})".Trim(), width - 14))
                    text.AppendLine($"{line,-28}{FormatMoney(-item.Monto),14}");
        }

        text.AppendLine(new string('=', width));
        text.Append("\u001b!\u0018");
        text.AppendLine($"{"Efectivo esperado:",-28}{FormatMoney(caja.TotalEfectivoEsperado ?? 0),14}");
        text.Append("\u001b!\u0008");
        text.AppendLine(new string('=', width));

        if (!string.IsNullOrWhiteSpace(caja.Observaciones))
        {
            foreach (var line in Wrap($"Obs: {caja.Observaciones}", width)) text.AppendLine(line);
        }
        text.AppendLine();
        text.AppendLine();
        text.AppendLine();
        return ToEscPos(text.ToString());
    }

    private static byte[] ToEscPos(string text, byte[]? trailer = null)
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
        return [.. initialize, .. readableFont, .. body, .. normalFont, .. (trailer ?? []), .. feedBeforeCut, .. cut];
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
