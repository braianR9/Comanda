using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

static class ProductComponentsRegression
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
            var stock = new StockMovementService(db);
            CreateProductRequest Request(string name, string type, List<ProductComponentRequest>? parts = null) => new() {
                Nombre = name, TipoProducto = type, IdRubro = seed.IdRubro, IdAlicuota = seed.IdAlicuota,
                PrecioConIva = 100, Componentes = parts,
                Stock = new() { StockActual = 100, OperacionCantidad = "Decimal", ComprobarStockAlVender = true }
            };
            var a = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba componente A", "ProductoSimple"));
            var b = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba componente B", "ProductoSimple"));
            var combo = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba combo", "ProductoCompuesto", [new() { ProductId = a.Id, Quantity = 2 }, new() { ProductId = b.Id, Quantity = .5m }]));
            Check(combo.Componentes.Count == 2, "Create persists and returns composition");
            await stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = a.Id, Quantity = 3 }, new() { ProductId = b.Id, Quantity = .5m }]);
            var reloaded = (await products.GetAsync(seed.IdEmpresa, combo.Id, branch.Id))!;
            Check(reloaded.Componentes.Single(c => c.ProductId == a.Id).Quantity == 3, "Editing quantities keeps components without duplicate tracking");
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = a.Id, Quantity = 0 }]), "Reject zero quantity");
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = a.Id, Quantity = .0001m }]), "Reject more than three decimals");
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = a.Id, Quantity = 1 }, new() { ProductId = a.Id, Quantity = 1 }]), "Reject duplicate component");
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = combo.Id, Quantity = 1 }]), "Reject self-reference");
            var otherCombo = await products.CreateAsync(seed.IdEmpresa, branch.Id, Request("Prueba otro combo", "ProductoCompuesto", [new() { ProductId = a.Id, Quantity = 1 }]));
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa, combo.Id, [new() { ProductId = otherCombo.Id, Quantity = 1 }]), "Reject nested compounds");
            await Reject(() => stock.SaveComponentsAsync(seed.IdEmpresa + 1000000, combo.Id, [new() { ProductId = a.Id, Quantity = 1 }]), "Reject other company");
            var options = await products.ComponentOptionsAsync(seed.IdEmpresa, "Prueba");
            Check(options.Any(p => p.Id == a.Id) && options.All(p => p.Id != combo.Id), "Picker includes simple products only");
            var sale = new Order { Id = -123456, IdEmpresa = seed.IdEmpresa, IdSucursal = branch.Id, Numero = 999,
                Items = [new OrderItem { ProductId = combo.Id, Quantity = 2, Estado = "Activo" }] };
            // Movimiento reference is an informational ID; no sale is opened or printed.
            await stock.ApplySaleAsync(sale, user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, a.Id, branch.Id))!.StockActual == 94, "Two combos deduct six units of A");
            Check((await products.GetStockAsync(seed.IdEmpresa, b.Id, branch.Id))!.StockActual == 99, "Two combos deduct one unit of B");
            Check((await products.GetStockAsync(seed.IdEmpresa, combo.Id, branch.Id))!.StockActual == 100, "Compound stock remains unchanged");
            await stock.ApplySaleAsync(sale, user.Id);
            await db.SaveChangesAsync();
            Check((await products.GetStockAsync(seed.IdEmpresa, a.Id, branch.Id))!.StockActual == 94, "Retry does not deduct stock twice");
            var invalid = new UpdateProductRequest { Nombre = "No guardar", TipoProducto = "ProductoCompuesto", IdRubro = seed.IdRubro,
                IdAlicuota = seed.IdAlicuota, PrecioConIva = 999, Componentes = [] };
            await Reject(() => products.UpdateAsync(seed.IdEmpresa, branch.Id, combo.Id, invalid), "Reject empty composition before saving product edits");
            Check((await products.GetAsync(seed.IdEmpresa, combo.Id, branch.Id))!.Nombre == "Prueba combo", "Invalid edit leaves product unchanged");
        }
        finally { await tx.RollbackAsync(); }
        Console.WriteLine("Product composition checks passed; all test changes rolled back.");
    }
    static void Check(bool condition, string label) { if (!condition) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string label)
    {
        try { await action(); }
        catch (Exception e) when (e is SaleException or ProductoException) { Console.WriteLine("PASS: " + label); return; }
        throw new Exception("Expected rejection: " + label);
    }
}
