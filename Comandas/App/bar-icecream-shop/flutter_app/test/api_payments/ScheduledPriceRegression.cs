using System.Data;
using System.Reflection;
using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

static class ScheduledPriceRegression
{
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); Console.WriteLine("PASS: " + message); }
    static async Task Reject(Func<Task> action, string message)
    {
        try { await action(); } catch (PriceListException) { Console.WriteLine("PASS: " + message); return; }
        throw new Exception("Expected rejection: " + message);
    }
    public static void Calendar()
    {
        var rule = new ScheduledPriceRule { Id = 1, FechaDesde = new(2026, 10, 2), FechaHasta = new(2026, 10, 2),
            DiasSemana = 1 << 4, MinutoDesde = 22 * 60, MinutoHasta = 2 * 60, Operacion = "DisminuirPorcentaje", Valor = 20 };
        bool Active(string time) => ScheduledPriceCalculator.IsActiveAt(rule, DateTimeOffset.Parse(time));
        Check(!Active("2026-10-02T21:59:59-03:00"), "Overnight rule is inactive before start");
        Check(Active("2026-10-02T22:00:00-03:00"), "Start boundary is included");
        Check(Active("2026-10-03T01:59:59-03:00"), "Friday overnight promotion continues on Saturday, including final occurrence");
        Check(!Active("2026-10-03T02:00:00-03:00"), "End boundary is excluded");
        Check(!Active("2026-10-03T22:00:00-03:00"), "Saturday does not start a Friday promotion");
        Check(!Active("2026-10-02T01:00:00-03:00"), "Previous occurrence before start date is excluded");
        Check(Active("2026-10-03T02:30:00Z"), "UTC server time is converted to Argentina time");
        rule.MinutoDesde = 18 * 60; rule.MinutoHasta = 20 * 60;
        Check(Active("2026-10-02T18:00:00-03:00") && !Active("2026-10-02T20:00:00-03:00"), "Same-day window boundaries");
        rule.MinutoDesde = rule.MinutoHasta = null;
        Check(Active("2026-10-02T00:00:00-03:00") && Active("2026-10-02T23:59:59-03:00"), "All-day rule includes entire final date");
        rule.Activa = false; Check(!Active("2026-10-02T19:00:00-03:00"), "Disabled rule never applies");
        rule.Activa = true; rule.FechaHasta = null; rule.DiasSemana = 127;
        Check(Active("2030-10-02T19:00:00-03:00"), "No end date supports permanent scheduled increases");
        var serialized = Newtonsoft.Json.JsonConvert.SerializeObject(rule);
        Check(Newtonsoft.Json.JsonConvert.DeserializeObject<ScheduledPriceRule>(serialized)!.FechaDesde == rule.FechaDesde,
            "Calendar dates survive API JSON serialization");
        var product = new Producto { Id = 5, IdRubro = 7, IdSubRubro = 8 };
        ScheduledPriceRule R(int id, int priority = 0, int? p = null, int? r = null, int? s = null) => new() {
            Id = id, Prioridad = priority, IdProducto = p, IdRubro = r, IdSubRubro = s,
            FechaDesde = new(2020, 1, 1), Operacion = "DisminuirPorcentaje", Valor = 10 };
        var instant = DateTimeOffset.Parse("2026-10-02T19:00:00-03:00");
        var all = R(1); var group = R(2, r: 7); var sub = R(3, s: 8); var specific = R(4, p: 5);
        Check(ScheduledPriceCalculator.Select([all, group, sub, specific], product, instant) == specific, "Product beats subcategory/category on equal priority");
        Check(ScheduledPriceCalculator.Select([all, group, sub], product, instant) == sub, "Subcategory beats category");
        all.Prioridad = 20;
        Check(ScheduledPriceCalculator.Select([all, specific], product, instant) == all, "Explicit priority beats specificity");
        Check(ScheduledPriceCalculator.Select([R(9, p: 5), specific], product, instant) == specific, "Tie is resolved by oldest rule id");
        Check(ScheduledPriceCalculator.Select([R(2, p: 99)], product, instant) == null, "Unrelated product rules do not apply");
        Check(ScheduledPriceCalculator.Calculate(1000, specific) == 900, "Only selected rule adjusts the base price");
        specific.Operacion = "PrecioFijo"; specific.Valor = 1234; specific.Redondeo = 100;
        Check(ScheduledPriceCalculator.Calculate(1000, specific) == 1300, "Fixed price supports rounding");
    }
    public static async Task Integration()
    {
        using var config = JsonDocument.Parse(File.ReadAllText("../../../Api/dotnet_api/src/appsettings.json"));
        var cs = config.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1")) throw new Exception("Only local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
        try
        {
            var product = await db.Productos.AsNoTracking().FirstAsync(p => p.Activo);
            var company = product.IdEmpresa;
            var service = new PriceListService(db);
            var list = await service.CreateAsync(company, new() { Nombre = "Reglas prueba " + Guid.NewGuid() });
            await service.SaveGridAsync(company, [new() { IdProducto = product.Id, IdListaPrecio = list.Id, PrecioNuevo = 1000 }], "Prueba");
            var request = new SaveScheduledPriceRuleRequest { Nombre = "Promo rubro", IdRubro = product.IdRubro,
                FechaDesde = new(2000, 1, 1), DiasSemana = 127, Operacion = "DisminuirPorcentaje", Valor = 20 };
            var rule = await service.SaveRuleAsync(company, list.Id, null, request, "Prueba");
            var instant = DateTimeOffset.Parse("2026-10-02T19:00:00-03:00");
            async Task<EffectivePriceDto> Quote() => (await service.QuotePricesAsync(company, 0,
                new() { IdListaPrecio = list.Id, ProductoIds = [product.Id], Fecha = instant })).Single();
            var branch = await db.Sucursales.FirstAsync(b => b.IdEmpresa == company);
            branch.IdListaPrecioPredeterminada = list.Id;
            await db.SaveChangesAsync();
            var automatic = (await service.QuotePricesAsync(company, branch.Id, new() { ProductoIds = [product.Id], Fecha = instant })).Single();
            Check(automatic.IdListaPrecio == list.Id && automatic.PrecioFinal == 800, "Branch default list is used when no list is specified");
            var count = await db.PriceHistory.CountAsync();
            var quote = await Quote();
            Check(quote.PrecioBase == 1000 && quote.PrecioFinal == 800 && quote.IdRegla == rule.Id, "Price lookup applies matching category promotion");
            Check(await db.PriceHistory.CountAsync() == count, "Price lookup does not mutate base prices or history");
            await Reject(() => service.RulesAsync(company + 1000000, list.Id), "Other companies cannot read rules");
            await Reject(() => service.QuotePricesAsync(company + 1000000, 0, new() { IdListaPrecio = list.Id, ProductoIds = [product.Id] }), "Other companies cannot quote this list");
            request.Version = 0;
            await Reject(() => service.SaveRuleAsync(company, list.Id, rule.Id, request, "Prueba"), "Stale rule edits are rejected");
            // Editing base prices must not use the discounted price as the old value.
            await service.SetPriceAsync(company, list.Id, product.Id, 2000, "Prueba");
            Check((await Quote()).PrecioFinal == 1600 && await service.ResolveBasePriceAsync(product.Id, list.Id) == 2000, "Base edit remains separate from scheduled adjustment");
            var orders = new OrderService(db, new ConfigurationBuilder().Build(), new StockMovementService(db), new CajaService(db), service);
            var add = typeof(OrderService).GetMethod("AddOrMergeItem", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var sale = new Order { IdEmpresa = company, IdListaPrecio = list.Id };
            await (Task)add.Invoke(orders, [sale, product.Id, 1m, null])!;
            Check(sale.Items.Single().UnitPrice == 1600, "New sale item uses scheduled price on the server");
            request.Version = rule.Version; request.Activa = false;
            await service.SaveRuleAsync(company, list.Id, rule.Id, request, "Prueba");
            Check((await Quote()).PrecioFinal == 2000, "Disabled rule restores base price without a background job");
            await (Task)add.Invoke(orders, [sale, product.Id, 1m, null])!;
            Check(sale.Items.Single().UnitPrice == 1600 && sale.Items.Single().Quantity == 2, "Existing sale line retains its stored price after promotion ends");
            request.Version = rule.Version; request.Activa = true; request.FechaDesde = new(2030, 1, 1);
            await service.SaveRuleAsync(company, list.Id, rule.Id, request, "Prueba");
            Check((await Quote()).PrecioFinal == 2000, "Future rule does not affect today's quote");
            request.Version = rule.Version; request.FechaDesde = new(2000, 1, 1); request.FechaHasta = new(2001, 1, 1);
            await service.SaveRuleAsync(company, list.Id, rule.Id, request, "Prueba");
            Check((await Quote()).PrecioFinal == 2000, "Expired rule falls back to base");
            request.MinutoDesde = 60; request.MinutoHasta = 60;
            await Reject(() => service.SaveRuleAsync(company, list.Id, null, request, "Prueba"), "Ambiguous equal start/end times are rejected");
            request.MinutoDesde = request.MinutoHasta = null; request.DiasSemana = 0;
            await Reject(() => service.SaveRuleAsync(company, list.Id, null, request, "Prueba"), "Empty weekday selection rejected");
            request.DiasSemana = 127; request.IdProducto = product.Id;
            await Reject(() => service.SaveRuleAsync(company, list.Id, null, request, "Prueba"), "Multiple target scopes rejected");
            request.IdProducto = null; request.IdRubro = -1;
            await Reject(() => service.SaveRuleAsync(company, list.Id, null, request, "Prueba"), "Unknown scope rejected");
            await service.SaveGridAsync(company, [new() { IdProducto = product.Id, IdListaPrecio = list.Id, PrecioAnterior = 2000, PrecioNuevo = null }], "Prueba");
            Check((await Quote()).PrecioFinal == null, "Product without base price remains unavailable");
            await service.SetActiveAsync(company, list.Id, false);
            await Reject(() => Quote(), "Inactive lists cannot be used for sales");
        }
        finally { await tx.RollbackAsync(); Console.WriteLine("All scheduled price test changes rolled back."); }
    }
}
