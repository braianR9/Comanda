using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using System.Text.Json;

static class LocalPaymentsIntegration
{
    public static async Task Run()
    {
        using var config = JsonDocument.Parse(File.ReadAllText("../../../Api/dotnet_api/src/appsettings.json"));
        var cs = config.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1"))
            throw new Exception("Only a local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            var seed = await db.Orders.AsNoTracking().Include(s => s.Items)
                .FirstAsync(s => s.Items.Any());
            var product = seed.Items[0];
            var sale = new Order {
                IdEmpresa = seed.IdEmpresa, IdSucursal = seed.IdSucursal, TableId = seed.TableId,
                Numero = await db.Orders.Where(s => s.IdEmpresa == seed.IdEmpresa).MaxAsync(s => s.Numero) + 1,
                UsuarioId = seed.UsuarioId, FechaApertura = DateTime.UtcNow,
                Estado = "PedidoEnviado", Subtotal = 100, Total = 100, Version = 1,
                Items = [new OrderItem { ProductId = product.ProductId, ProductName = "Payment regression", UnitPrice = 100, Quantity = 1, Subtotal = 100, FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow }],
                Commands = [new KitchenCommand {
                    IdEmpresa = seed.IdEmpresa, TableId = seed.TableId, UsuarioId = seed.UsuarioId,
                    Numero = (await db.Set<KitchenCommand>().Where(c => c.IdEmpresa == seed.IdEmpresa).MaxAsync(c => (int?)c.Numero) ?? 0) + 1,
                    Tipo = "Inicial", Fecha = DateTime.UtcNow,
                    Lines = [new KitchenCommandLine { ProductId = product.ProductId, ProductName = "Payment regression", CurrentQuantity = 1, QuantityDelta = 1 }]
                }]
            };
            var cash = new Card { IdEmpresa = seed.IdEmpresa, Nombre = "Regression cash " + Guid.NewGuid(), TipoAjuste = "Descuento", Porcentaje = 10, Activa = true };
            var card = new Card { IdEmpresa = seed.IdEmpresa, Nombre = "Regression card " + Guid.NewGuid(), TipoAjuste = "Recargo", Porcentaje = 20, Activa = true };
            db.Orders.Add(sale); db.Cards.AddRange(cash, card);
            await db.SaveChangesAsync();
            var service = new OrderService(db, new ConfigurationBuilder().Build(), new StockMovementService(db), new CajaService(db), new PriceListService(db));
            var first = await service.AddPaymentsAsync(seed.IdEmpresa, seed.IdSucursal, seed.UsuarioId, sale.Id,
                new AddPaymentsRequest([new PaymentRequest(null, 36, null, cash.Id, 40)], 1));
            Require(first.Total == 96 && first.PaymentAdjustment == -4 && first.Version == 2, "Partial discounted payment persisted");
            await Reject(() => service.ApplyDiscountAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id,
                new ApplyDiscountRequest(null, "Blocked", "Porcentaje", 5, first.Version)), "Editing blocked after partial payment");
            await Reject(() => service.AddPaymentsAsync(seed.IdEmpresa, seed.IdSucursal, seed.UsuarioId, sale.Id,
                new AddPaymentsRequest([new PaymentRequest(null, 60, null, card.Id, 60)], first.Version)), "Stale percentage/incorrect amount rejected");
            var second = await service.AddPaymentsAsync(seed.IdEmpresa, seed.IdSucursal, seed.UsuarioId, sale.Id,
                new AddPaymentsRequest([new PaymentRequest(null, 72, null, card.Id, 60)], first.Version));
            Require(second.Total == 108 && second.PaymentAdjustment == 8 && second.Version == 3, "Mixed payment final total persisted");
            db.ChangeTracker.Clear();
            var stored = await db.Orders.AsNoTracking().Include(s => s.Payments).SingleAsync(s => s.Id == sale.Id);
            Require(stored.Payments.Sum(p => p.Amount) == stored.Total && stored.Payments.Sum(p => p.BaseAmount) == 100,
                "Reloaded amounts cover the account and adjusted total exactly");
            await Reject(() => service.AddPaymentsAsync(seed.IdEmpresa, seed.IdSucursal, seed.UsuarioId, sale.Id,
                new AddPaymentsRequest([new PaymentRequest(null, 9, null, cash.Id, 10)], second.Version)), "Excess allocation rejected");
            // Altering the catalog must not alter a historical payment or reprint.
            var savedCard = await db.Cards.SingleAsync(c => c.Id == card.Id);
            savedCard.Porcentaje = 30;
            await db.SaveChangesAsync();
            var historical = await db.SalePayments.AsNoTracking().SingleAsync(p => p.OrderId == sale.Id && p.CardId == card.Id);
            Require(historical.Percentage == 20 && historical.Amount == 72 && historical.AdjustmentAmount == 12,
                "Catalog edits preserve recorded payment adjustments");
        }
        finally
        {
            await transaction.RollbackAsync();
            Console.WriteLine("Local regression transaction rolled back; no ticket enqueued.");
        }
    }

    private static void Require(bool ok, string description)
    {
        if (!ok) throw new Exception(description);
        Console.WriteLine("PASS: " + description);
    }
    private static async Task Reject(Func<Task<SaleDto>> operation, string description)
    {
        try { await operation(); }
        catch (SaleException) { Console.WriteLine("PASS: " + description); return; }
        throw new Exception(description);
    }
}
