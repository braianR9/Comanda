using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;

static class StockSaleRegression
{
    public static async Task Run()
    {
        var cs = TestConfig.ConnectionString();
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1"))
            throw new Exception("Only the local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            var seed = await db.Productos.AsNoTracking().FirstAsync(p => p.Activo);
            var branch = await db.Sucursales.AsNoTracking().FirstAsync(b => b.IdEmpresa == seed.IdEmpresa);
            var user = await db.Usuarios.AsNoTracking().FirstAsync(u => u.IdEmpresa == seed.IdEmpresa);
            var products = new ProductoService(db, new PriceListService(db));
            var movements = new StockMovementService(db);
            var sequence = 0;
            CreateProductRequest Request(string name, ProductStockRequest? stock = null) => new() {
                Nombre = name, IdRubro = seed.IdRubro, IdAlicuota = seed.IdAlicuota, PrecioConIva = 100, Stock = stock
            };
            // Only informational movement references are created: no orders,
            // payments, fiscal invoices or print jobs are opened by this test.
            Order Sale(int product, decimal quantity = 1) => new() {
                Id = -1900000000 + ++sequence, IdEmpresa = seed.IdEmpresa, IdSucursal = branch.Id, Numero = 999,
                Items = [new() { ProductId = product, Quantity = quantity, Estado = "Activo" }]
            };
            Task Validate(int product, decimal quantity = 1) => movements.ValidateSelectionAsync(
                seed.IdEmpresa, branch.Id, [new(product, quantity, null)]);
            var untracked = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba venta sin configurar stock"));
            await Validate(untracked.Id);
            await movements.ApplySaleAsync(Sale(untracked.Id), user.Id);
            await db.SaveChangesAsync();
            Check(!await db.StockProductos.AnyAsync(s => s.IdProducto == untracked.Id), "Unconfigured product can sell without creating fictitious stock");
            Check(!await db.StockMovements.AnyAsync(s => s.ProductId == untracked.Id), "Unconfigured product does not record stock movements");

            var uncheckedProduct = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba venta control desactivado", new() {
                StockActual = 0, ComprobarStockAlVender = false, TieneAlarmaStock = true, TieneAlarmaStockMinimo = true
            }));
            await Validate(uncheckedProduct.Id);
            await movements.ApplySaleAsync(Sale(uncheckedProduct.Id), user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, uncheckedProduct.Id, branch.Id))!.StockActual == 0,
                "Stock alarms alone do not block a sale when check-on-sale is off");

            var checkedProduct = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba venta control activado", new() {
                StockActual = 0, ComprobarStockAlVender = true, TieneAlarmaStock = false
            }));
            await Reject(() => Validate(checkedProduct.Id), "Selection blocks insufficient stock when check-on-sale is enabled");
            Check(!await db.StockMovements.AnyAsync(m => m.ProductId == checkedProduct.Id), "Rejected sale records no stock movement");
            await products.UpsertStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id, new() { StockActual = 3, ComprobarStockAlVender = true });
            await Validate(checkedProduct.Id, 2);
            Check((await products.GetStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id))!.StockActual == 3,
                "Selection validation does not deduct inventory");
            await Reject(() => Validate(checkedProduct.Id, 4), "Increasing selected quantity beyond available stock is rejected");
            var trackedSale = Sale(checkedProduct.Id, 2);
            await movements.ApplySaleAsync(trackedSale, user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id))!.StockActual == 1, "Checked product sells and deducts available stock");
            await movements.ApplySaleAsync(trackedSale, user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id))!.StockActual == 1, "Sale retry does not deduct stock twice");

            var comboRequest = Request("Prueba combo componente sin stock");
            comboRequest.TipoProducto = "ProductoCompuesto";
            comboRequest.Componentes = [new() { ProductId = untracked.Id, Quantity = 1 }];
            var combo = await products.CreateAsync(seed.IdEmpresa, branch.Id, comboRequest);
            await Validate(combo.Id);
            await movements.ApplySaleAsync(Sale(combo.Id), user.Id);
            await db.SaveChangesAsync();
            Check(!await db.StockMovements.AnyAsync(m => m.ProductId == untracked.Id), "Composite can sell components without stock configured");
            comboRequest.Nombre = "Prueba combo con control de stock";
            comboRequest.Componentes = [new() { ProductId = checkedProduct.Id, Quantity = 2 }];
            var controlledCombo = await products.CreateAsync(seed.IdEmpresa, branch.Id, comboRequest);
            await Reject(() => Validate(controlledCombo.Id), "Selecting a composite checks its components");
            await Reject(() => movements.ValidateSelectionAsync(seed.IdEmpresa, branch.Id,
                [new(checkedProduct.Id, 1, null), new(checkedProduct.Id, 1, null)]),
                "Repeated product lines are checked as one total quantity");
            await products.UpsertStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id,
                new() { StockActual = 2, ComprobarStockAlVender = true });
            await Validate(controlledCombo.Id);
            await Reject(() => movements.ValidateSelectionAsync(seed.IdEmpresa, branch.Id,
                [new(checkedProduct.Id, 1, null), new(controlledCombo.Id, 1, null)]),
                "Simple products and composites share the component's available stock");
            // Availability can change after selection; payment must not be blocked.
            await products.UpsertStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id,
                new() { StockActual = 0, ComprobarStockAlVender = true });
            await movements.ApplySaleAsync(Sale(controlledCombo.Id), user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, checkedProduct.Id, branch.Id))!.StockActual == 0,
                "Checkout records consumption without rejecting an already selected product for insufficient stock");
            await Reject(() => movements.ReceivePurchaseAsync(seed.IdEmpresa, branch.Id, user.Id,
                0, untracked.Id, 1, "Prueba sin configuración"), "Purchases still require stock configuration");
        }
        finally { await tx.RollbackAsync(); }
        Console.WriteLine("Stock sale checks passed; all test changes rolled back.");
    }
    static void Check(bool condition, string label) { if (!condition) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string label)
    {
        try { await action(); }
        catch (SaleException ex) when (ex.StatusCode == 409) { Console.WriteLine("PASS: " + label); return; }
        throw new Exception("Expected rejection: " + label);
    }
}
