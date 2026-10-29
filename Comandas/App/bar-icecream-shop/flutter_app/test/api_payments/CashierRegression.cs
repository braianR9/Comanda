using System.Reflection;
using System.Security.Claims;
using BarIceCreamShop.Api.Controllers;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

static class CashierRegression
{
    public static async Task Run()
    {
        ClaimsPrincipal Principal(string role) => new(new ClaimsIdentity([new Claim("rol_nombre", role)], "Regression"));
        foreach (var role in new[] { "ADMIN", "CAJA", "ENCARGADO" })
            Check(SalePermissions.CanCollect(Principal(role)), role + " can collect payments");
        Check(!SalePermissions.CanCollect(Principal("EMPLEADO")), "Employees cannot collect payments");
        Check(!SalePermissions.CanCollect(Principal("OTHER")) && !SalePermissions.CanCollect(new()), "Unknown/anonymous roles cannot collect payments");
        foreach (var name in new[] { "Payments", "Checkout", "ItemPrice", "Discount", "RemoveDiscount", "PriceList" })
            Check(typeof(SalesController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>()
                .Any(a => a.Policy == SalePermissions.CashierPolicy), name + " enforces cashier authorization");
        Check(typeof(InvoicesController).GetCustomAttributes<AuthorizeAttribute>()
            .Any(a => a.Policy == SalePermissions.CashierPolicy), "Fiscal/payment ticket operations enforce cashier authorization");
        Check(SalePermissions.RoleName("ENCARGADO") == "CAJA", "Existing managers are displayed as Caja without replacing users");

        var cs = TestConfig.ConnectionString();
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1"))
            throw new Exception("Only the local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            var seed = await db.Orders.AsNoTracking().Include(s => s.Items).FirstAsync(s => s.Items.Any());
            var product = await db.Productos.AsNoTracking().SingleAsync(p => p.Id == seed.Items[0].ProductId);
            var catalogPrice = product.PrecioConIva;
            var listPrices = await db.ProductoPrecios.AsNoTracking().Where(p => p.IdProducto == product.Id)
                .OrderBy(p => p.IdListaPrecio).Select(p => p.Precio).ToListAsync();
            var sale = new Order {
                IdEmpresa = seed.IdEmpresa, IdSucursal = seed.IdSucursal, TableId = seed.TableId,
                Numero = await db.Orders.Where(s => s.IdEmpresa == seed.IdEmpresa).MaxAsync(s => s.Numero) + 1,
                UsuarioId = seed.UsuarioId, FechaApertura = DateTime.UtcNow, Estado = "PedidoEnviado",
                Subtotal = 200, Total = 180, Version = 1, DescuentoTipo = "Porcentaje", DescuentoValor = 10,
                ImporteDescuento = 20,
                Items = [new() { ProductId = product.Id, ProductName = product.Nombre, UnitPrice = 100, Quantity = 2, Subtotal = 200,
                    FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow }],
                Commands = [new() { IdEmpresa = seed.IdEmpresa, TableId = seed.TableId, UsuarioId = seed.UsuarioId,
                    Numero = (await db.KitchenCommands.Where(c => c.IdEmpresa == seed.IdEmpresa).MaxAsync(c => (int?)c.Numero) ?? 0) + 1,
                    Tipo = "Inicial", Fecha = DateTime.UtcNow,
                    Lines = [new() { ProductId = product.Id, ProductName = product.Nombre, CurrentQuantity = 2, QuantityDelta = 2 }] }]
            };
            db.Orders.Add(sale); await db.SaveChangesAsync();
            var config = new ConfigurationBuilder().Build();
            var orders = new OrderService(db, config, new(db), new(db), new(db), TestConfig.Invoices(db, config));
            var changed = await orders.ChangeItemPriceAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id, sale.Items[0].Id, new(150, 1));
            Check(changed.Items.Single().UnitPrice == 150 && changed.Subtotal == 300 && changed.DiscountAmount == 30 && changed.Total == 270,
                "Price override recalculates line, subtotal, discount and total");
            Check(changed.Version == 2 && changed.Status == "PedidoEnviado", "Price override preserves kitchen status and advances concurrency version");
            Check((await db.Productos.AsNoTracking().SingleAsync(p => p.Id == product.Id)).PrecioConIva == catalogPrice,
                "Price override leaves catalog price unchanged");
            Check(listPrices.SequenceEqual(await db.ProductoPrecios.AsNoTracking().Where(p => p.IdProducto == product.Id)
                .OrderBy(p => p.IdListaPrecio).Select(p => p.Precio).ToListAsync()), "Price override leaves every price list unchanged");
            await Reject(() => orders.ChangeItemPriceAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id, sale.Items[0].Id, new(170, 1)),
                "Stale version cannot overwrite a newer account price");
            await Reject(() => orders.ChangeItemPriceAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id, sale.Items[0].Id, new(-1, 2)),
                "Negative unit price is rejected");
            Check((await orders.GetAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id))!.Items.Single().UnitPrice == 150,
                "Reloading account preserves the override");
            sale.Payments.Add(new() { PaymentTypeName = "Prueba", Amount = 1, BaseAmount = 1, Fecha = DateTime.UtcNow, UsuarioId = seed.UsuarioId });
            await db.SaveChangesAsync();
            await Reject(() => orders.ChangeItemPriceAsync(seed.IdEmpresa, seed.IdSucursal, sale.Id, sale.Items[0].Id, new(160, 2)),
                "Price changes are blocked after recording a payment");
        }
        finally { await tx.RollbackAsync(); }
        Console.WriteLine("Cashier checks passed. Test rows rolled back; no payments were collected or printed.");
    }
    static void Check(bool condition, string label) { if (!condition) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string label) {
        try { await action(); } catch (SaleException) { Console.WriteLine("PASS: " + label); return; }
        throw new Exception("Expected rejection: " + label);
    }
}
