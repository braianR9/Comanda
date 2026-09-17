using System.Reflection;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;

if (args.Contains("--test-local-payments"))
{
    await LocalPaymentsIntegration.Run();
    return;
}

if (args.Contains("--migrate-local-payments") || args.Contains("--check-local-payments"))
{
    var apiRoot = Path.GetFullPath("../../../Api/dotnet_api");
    using var config = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(apiRoot, "src/appsettings.json")));
    var connectionString = config.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
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
var receipt = System.Text.Encoding.ASCII.GetString((byte[])printMethod.Invoke(null, [receiptSale, "Local", "", null, null, "Mozo"])!);
Check(receipt.Contains("DESC. PAGO Efectivo 10%") && receipt.Contains("RECARGO Tarjeta 20%"), "Receipt identifies payment discounts and surcharges");
Check(receipt.Contains("108,00") && receipt.Contains("36,00") && receipt.Contains("72,00"), "Receipt prints adjusted total and each payment amount");
