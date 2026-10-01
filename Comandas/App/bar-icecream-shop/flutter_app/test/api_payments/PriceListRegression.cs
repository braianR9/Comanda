using System.Data;
using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;

static class PriceListRegression
{
    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
        Console.WriteLine("PASS: " + message);
    }
    static async Task Reject(Func<Task> action, string message)
    {
        try { await action(); } catch (PriceListException) { Console.WriteLine("PASS: " + message); return; }
        throw new Exception("Expected rejection: " + message);
    }
    public static void Calculations()
    {
        foreach (var (mode, expected) in new[] { ("Arriba", 1200m), ("Abajo", 1100m), ("Cercano", 1100m) })
            Check(PriceListService.CalculatePrice(1010m, new() { Operacion = "AumentarPorcentaje", Valor = 10, Redondeo = 100, ModoRedondeo = mode }) == expected,
                "10% increase rounded " + mode);
        Check(PriceListService.CalculatePrice(100m, new() { Operacion = "DisminuirImporte", Valor = 200, Redondeo = 100 }) == 0,
            "Discount does not create negative prices");
        Check(PriceListService.CalculatePrice(1.05m, new() { Operacion = "AumentarPorcentaje", Valor = 10 }) == 1.16m,
            "Half cents round away from zero");
        Check(PriceListService.CalculatePrice(1000m, new() { Operacion = "AumentarImporte", Valor = 0, Redondeo = 100 }) == 1000,
            "Exact multiples do not move");
        foreach (var request in new BulkPriceOperationRequest[] {
            new() { Operacion = "Invalid" }, new() { Operacion = "AumentarImporte", Redondeo = -1 },
            new() { Operacion = "AumentarImporte", ModoRedondeo = "Invalid" },
            new() { Operacion = "DisminuirPorcentaje", Valor = 101 },
            new() { Operacion = "AumentarImporte", Redondeo = 0.001m },
            new() { Operacion = "AumentarImporte", Valor = 9999999999999999.99m } })
        {
            var rejected = false;
            try { PriceListService.CalculatePrice(100m, request); } catch (PriceListException) { rejected = true; }
            Check(rejected, "Invalid or overflowing calculation rejected");
        }
    }
    public static async Task Integration()
    {
        using var config = JsonDocument.Parse(File.ReadAllText("../../../Api/dotnet_api/src/appsettings.json"));
        var cs = config.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1"))
            throw new Exception("Only the local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
        try
        {
            var product = await db.Productos.AsNoTracking().FirstAsync(p => p.Activo);
            var company = product.IdEmpresa;
            var service = new PriceListService(db);
            var a = await service.CreateAsync(company, new() { Nombre = "Prueba planilla " + Guid.NewGuid() });
            var b = await service.CreateAsync(company, new() { Nombre = "Prueba comparación " + Guid.NewGuid() });
            PriceCellChange Cell(int list, decimal? before, decimal? after) => new() {
                IdListaPrecio = list, IdProducto = product.Id, PrecioAnterior = before, PrecioNuevo = after };
            await service.SaveGridAsync(company, [Cell(a.Id, null, 1010), Cell(b.Id, null, 1500)], "Prueba automática");
            var initial = await db.PriceHistory.AsNoTracking().Where(h => h.IdListaPrecio == a.Id).SingleAsync();
            Check(initial.PrecioAnterior == null && initial.PrecioNuevo == 1010 && initial.Usuario == "Prueba automática", "History records actor and old/new values");
            Check(await db.PriceHistory.CountAsync(h => h.Lote == initial.Lote) == 2, "Multiple lists saved in one history group");
            await Reject(() => service.SaveGridAsync(company, [Cell(a.Id, 1010, 1200), Cell(b.Id, 999, 1600)], "Prueba"), "Stale batch rejected entirely");
            Check(await service.ResolvePriceAsync(product.Id, a.Id) == 1010, "Rejected batch leaves first price untouched");
            await Reject(() => service.SaveGridAsync(company + 1000000, [Cell(a.Id, 1010, 1200)], "Prueba"), "Other companies cannot change prices");
            await Reject(() => service.SaveGridAsync(company, [Cell(a.Id, 1010, 1), Cell(a.Id, 1010, 2)], "Prueba"), "Duplicate cells rejected");
            await Reject(() => service.SaveGridAsync(company, [Cell(a.Id, 1010, -1)], "Prueba"), "Negative prices rejected");
            await Reject(() => service.SaveGridAsync(company, [Cell(a.Id, 1010, 1.001m)], "Prueba"), "Fractional cents rejected");
            var bulk = new BulkPriceOperationRequest { Operacion = "AumentarPorcentaje", Valor = 10, Redondeo = 100,
                Filtro = new() { ProductoIds = [product.Id] } };
            var preview = await service.PreviewBulkAsync(company, a.Id, bulk);
            Check(preview.Single().PrecioNuevo == 1200, "Bulk preview includes rounding");
            bulk.CambiosConfirmados = preview.Select(p => Cell(a.Id, p.PrecioActual, p.PrecioNuevo)).ToList();
            await service.ApplyBulkAsync(company, a.Id, bulk, "Prueba masiva");
            Check(await service.ResolvePriceAsync(product.Id, a.Id) == 1200, "Bulk saves the exact preview");
            await Reject(() => service.ApplyBulkAsync(company, a.Id, bulk, "Prueba"), "Repeated stale preview cannot apply twice");
            await Reject(() => service.RevertAsync(company, initial.Lote, "Prueba"), "History cannot overwrite later changes");
            var latest = await db.PriceHistory.AsNoTracking().Where(h => h.IdListaPrecio == a.Id).OrderByDescending(h => h.Id).FirstAsync();
            await service.RevertAsync(company, latest.Lote, "Prueba reversión");
            Check(await service.ResolvePriceAsync(product.Id, a.Id) == 1010, "Revert restores original price");
            await Reject(() => service.RevertAsync(company, latest.Lote, "Prueba"), "Cannot revert the same batch twice");
            await service.SaveGridAsync(company, [Cell(b.Id, 1500, null)], "Prueba quitar");
            Check(await service.ResolvePriceAsync(product.Id, b.Id) == null, "Blank cell removes configured price");
            var removed = await db.PriceHistory.AsNoTracking().Where(h => h.IdListaPrecio == b.Id).OrderByDescending(h => h.Id).FirstAsync();
            await service.RevertAsync(company, removed.Lote, "Prueba");
            Check(await service.ResolvePriceAsync(product.Id, b.Id) == 1500, "Revert restores removed price");
            var count = await db.PriceHistory.CountAsync();
            await service.SaveGridAsync(company, [Cell(b.Id, 1500, 1500)], "Prueba");
            Check(await db.PriceHistory.CountAsync() == count, "Unchanged prices do not create history");
            var history = await service.HistoryAsync(company, 1);
            Check(history != null, "History pagination query executes");
            Check((await service.HistoryDetailsAsync(company + 1000000, latest.Lote)).Count == 0, "History is isolated by company");
        }
        finally { await transaction.RollbackAsync(); Console.WriteLine("Rolled back all integration test changes."); }
    }
}
