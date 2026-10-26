using System.Reflection;
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;

if (args.Contains("--test-afip"))
{
    await AfipRegression.Run(live: args.Contains("--live"));
    return;
}

if (args.Contains("--test-purchases"))
{
    await PurchasesRegression.Run();
    return;
}

if (args.Contains("--test-product-components"))
{
    await ProductComponentsRegression.Run();
    return;
}

if (args.Contains("--test-scheduled-prices"))
{
    ScheduledPriceRegression.Calendar();
    await ScheduledPriceRegression.Integration();
    return;
}

if (args.Contains("--test-price-calculations"))
{
    PriceListRegression.Calculations();
    return;
}
if (args.Contains("--test-price-lists"))
{
    PriceListRegression.Calculations();
    await PriceListRegression.Integration();
    return;
}

if (args.Contains("--test-decimal-validation"))
{
    var originalCulture = CultureInfo.CurrentCulture;
    try
    {
        foreach (var culture in new[] { "es-AR", "en-US" })
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo(culture);
            var ranges = typeof(Order).Assembly.GetTypes()
                .SelectMany(type => type.GetProperties().Cast<ICustomAttributeProvider>()
                    .Concat(type.GetConstructors().SelectMany(c => c.GetParameters())))
                .SelectMany(member => member.GetCustomAttributes(typeof(RangeAttribute), false).Cast<RangeAttribute>())
                .Where(range => range.OperandType == typeof(decimal)).ToList();
            if (ranges.Count == 0) throw new Exception("No decimal validators found.");
            foreach (var range in ranges)
            {
                var min = Convert.ToDecimal(range.Minimum, CultureInfo.InvariantCulture);
                var max = Convert.ToDecimal(range.Maximum, CultureInfo.InvariantCulture);
                if (!range.IsValid(min) || !range.IsValid(max) || !range.IsValid((min + max) / 2)
                    || range.IsValid(min - 0.001m) || range.IsValid(max + 0.001m))
                    throw new Exception($"Incorrect decimal validation in {culture}.");
            }
            Console.WriteLine($"PASS: {ranges.Count} decimal validators accept boundaries and reject out-of-range values in {culture}.");
        }
    }
    finally { CultureInfo.CurrentCulture = originalCulture; }
    return;
}

if (args.Contains("--test-local-payments"))
{
    await LocalPaymentsIntegration.Run();
    return;
}

if (args.Contains("--migrate-local-payments") || args.Contains("--check-local-payments"))
{
    var apiRoot = Path.GetFullPath("../../../Api/dotnet_api");
    var connectionString = TestConfig.ConnectionString(apiRoot);
    var settings = new Npgsql.NpgsqlConnectionStringBuilder(connectionString);
    if (settings.Host is not ("localhost" or "127.0.0.1" or "::1")) throw new Exception("Only the configured local database may be migrated by this command.");
    await using var connection = new Npgsql.NpgsqlConnection(connectionString);
    await connection.OpenAsync();
    if (args.Contains("--check-local-payments"))
    {
        await using var check = new Npgsql.NpgsqlCommand("SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'venta_pagos' AND column_name IN ('id_tarjeta', 'importe_base', 'tipo_ajuste', 'porcentaje', 'importe_ajuste')", connection);
        var count = Convert.ToInt32(await check.ExecuteScalarAsync());
        Console.WriteLine(count == 5 ? "Payment adjustment columns are present." : "Payment adjustment migration is still pending.");
        return;
    }
    await using var migration = new Npgsql.NpgsqlCommand(File.ReadAllText(Path.Combine(apiRoot, "database/add_payment_adjustments.sql")), connection);
    await migration.ExecuteNonQueryAsync();
    Console.WriteLine("Local payment adjustment migration applied.");
    return;
}

// Exercise the state returned to clients for legacy discount-only changes,
// while ensuring actual kitchen edits still prevent checkout.
var map = typeof(OrderService).GetMethod("Map", BindingFlags.Static | BindingFlags.NonPublic)!;
string Status(Order sale) => ((SaleDto)map.Invoke(null, [sale])!).Status;
void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
    Console.WriteLine($"PASS: {message}");
}
var sale = new Order {
    Estado = "ConCambios", DescuentoTipo = "Porcentaje", DescuentoValor = 10,
    Items = [new OrderItem { ProductId = 1, Quantity = 2 }],
    Commands = [new KitchenCommand {
        Id = 1, Fecha = DateTime.UtcNow,
        Lines = [new KitchenCommandLine { ProductId = 1, CurrentQuantity = 2 }]
    }]
};
Check(Status(sale) == "PedidoEnviado", "Discount alone does not require a kitchen command");
sale.Payments.Add(new SalePayment { Amount = 90 });
Check(Status(sale) == "PedidoEnviado", "Previously recorded payment can resume closing");
sale.Items[0].Quantity = 1;
Check(Status(sale) == "ConCambios", "Quantity changes remain pending");
sale.Items[0].Quantity = 2;
sale.Items[0].Comment = "Sin azúcar";
Check(Status(sale) == "ConCambios", "Comment changes remain pending");
sale.Items.Clear();
Check(Status(sale) == "ConCambios", "Removed products remain pending");
sale.Commands.Add(new KitchenCommand {
    Id = 2, Fecha = sale.Commands[0].Fecha,
    Lines = [new KitchenCommandLine { ProductId = 1, CurrentQuantity = 0 }]
});
Check(Status(sale) == "PedidoEnviado", "Latest command resolves an acknowledged removal");
sale.Estado = "Finalizada";
Check(Status(sale) == "Finalizada", "Finalized sales stay finalized");

var surcharge = PaymentCalculation.Calculate(100, "Recargo", 10);
Check(surcharge.Total == 110 && surcharge.Adjustment == 10, "10% surcharge on assigned amount");
var discount = PaymentCalculation.Calculate(100, "Descuento", 15);
Check(discount.Total == 85 && discount.Adjustment == -15, "15% payment discount");
var cash = PaymentCalculation.Calculate(40, "Descuento", 10);
var card = PaymentCalculation.Calculate(60, "Recargo", 20);
Check(cash.Total + card.Total == 108, "Mixed payments apply each percentage only to its portion");
Check(PaymentCalculation.Calculate(0.05m, "Recargo", 10).Total == 0.06m, "Half cent rounds away from zero");
Check(PaymentCalculation.Calculate(90, "Descuento", 100).Total == 0, "100% discount covers the assigned base with zero charged");
Check(PaymentCalculation.Calculate(90, "SinAjuste", 0).Total == 90, "No adjustment preserves the amount");
foreach (var invalid in new[] { (0m, "Recargo", 10m), (100m, "Descuento", 101m), (100m, "Invalid", 10m) })
{
    var rejected = false;
    try { PaymentCalculation.Calculate(invalid.Item1, invalid.Item2, invalid.Item3); }
    catch (SaleException) { rejected = true; }
    Check(rejected, "Invalid payment adjustment rejected");
}

var printMethod = typeof(PrintJobWorker).GetMethod("BuildSaleTicket", BindingFlags.Static | BindingFlags.NonPublic)!;
var receiptSale = new Order { Numero = 99, Total = 108, Subtotal = 100,
    Payments = [
        new SalePayment { PaymentTypeName = "Efectivo", BaseAmount = 40, Amount = 36, AdjustmentAmount = -4, AdjustmentType = "Descuento", Percentage = 10 },
        new SalePayment { PaymentTypeName = "Tarjeta", BaseAmount = 60, Amount = 72, AdjustmentAmount = 12, AdjustmentType = "Recargo", Percentage = 20 }
    ] };
var receipt = System.Text.Encoding.ASCII.GetString((byte[])printMethod.Invoke(null, [receiptSale, "Local", "", null, null, "Mozo", null, null, false])!);
Check(receipt.Contains("DESC. PAGO Efectivo 10%") && receipt.Contains("RECARGO Tarjeta 20%"), "Receipt identifies payment discounts and surcharges");
Check(receipt.Contains("108,00") && receipt.Contains("36,00") && receipt.Contains("72,00"), "Receipt prints adjusted total and each payment amount");
var fiscalInvoice = new Invoice { Status = "Autorizado", Type = AfipCodes.FacturaB, PointOfSale = 3, Number = 15, Date = new DateOnly(2026, 10, 22),
    Cae = "75123456789012", CaeExpiresAt = new DateOnly(2026, 11, 1), Total = 108, Net = 89.26m, Vat = 18.74m,
    DocType = AfipCodes.DocSinIdentificar, ReceiverVatCondition = AfipCodes.CondConsumidorFinal, Environment = "Homologacion",
    VatJson = "[{\"id\":5,\"rate\":21,\"baseAmount\":89.26,\"amount\":18.74}]" };
var fiscalBilling = new BillingSettings { LegalName = "Heladeria Prueba SRL", Cuit = "20111111112", TaxCondition = "Responsable Inscripto" };
var fiscal = System.Text.Encoding.ASCII.GetString((byte[])printMethod.Invoke(null, [receiptSale, "Local", "", null, null, "Mozo", fiscalInvoice, fiscalBilling, false])!);
Check(fiscal.Contains("FACTURA B") && fiscal.Contains("00003-00000015") && fiscal.Contains("CAE: 75123456789012"), "Fiscal ticket prints type, number and CAE");
Check(fiscal.Contains("IVA contenido") && fiscal.Contains("18,74") && !fiscal.Contains("NO VALIDO COMO FACTURA"), "Fiscal ticket shows contained VAT (Ley 27.743)");
Check(fiscal.Contains("afip.gob.ar/fe/qr/?p=") && fiscal.Contains("HOMOLOGACION"), "Fiscal ticket embeds AFIP QR and test-environment warning");
var creditNote = new Invoice { Status = "Autorizado", Type = AfipCodes.NotaCreditoB, PointOfSale = 3, Number = 2, Date = new DateOnly(2026, 10, 23),
    Cae = "75123456789099", CaeExpiresAt = new DateOnly(2026, 11, 2), Total = 108, Net = 89.26m, Vat = 18.74m,
    DocType = AfipCodes.DocSinIdentificar, ReceiverVatCondition = AfipCodes.CondConsumidorFinal, Environment = "Homologacion",
    VatJson = fiscalInvoice.VatJson, Reason = "Devolucion", AssociatedLabel = "Factura B 00003-00000015" };
var noteTicket = System.Text.Encoding.ASCII.GetString((byte[])printMethod.Invoke(null, [receiptSale, "Local", "", null, null, "Mozo", creditNote, fiscalBilling, true])!);
Check(noteTicket.Contains("NOTA DE CREDITO B") && noteTicket.Contains("Anula: Factura B 00003-00000015") && noteTicket.Contains("Motivo: Devolucion"), "Credit note ticket shows annulled invoice and reason");
Check(noteTicket.Contains("REIMPRESION") && noteTicket.Contains("IVA contenido") && !fiscal.Contains("REIMPRESION"), "Reprints are marked; original prints are not");
