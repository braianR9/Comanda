using System.Text.Json;
using System.Security.Claims;
using BarIceCreamShop.Api.Controllers;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;

static class PurchasesRegression
{
    static string Cs = "";
    static AppDbContext Db() => new(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(Cs, o => o.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)).Options);
    static PurchaseService Service(AppDbContext db) => new(db, new StockMovementService(db));
    static JsonElement Json(object o) => JsonSerializer.SerializeToElement(o);
    static async Task<T> With<T>(Func<AppDbContext, Task<T>> work) { await using var db = Db(); return await work(db); }
    static PurchaseRequest Request(int supplier, string number, params PurchaseItemRequest[] items) => new() {
        SupplierId = supplier, DocumentType = "Remito", Number = number, DocumentDate = DateOnly.FromDateTime(DateTime.Today),
        RequestKey = Guid.NewGuid().ToString(), Items = items.ToList()
    };
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string label) {
        try { await action(); } catch (Exception e) when (e is PurchaseException or SaleException) { Console.WriteLine("PASS: " + label); return; }
        throw new Exception("Expected rejection: " + label);
    }
    public static async Task Run()
    {
        Cs = Environment.GetEnvironmentVariable("COMPRAS_TEST_CONNECTION") ?? throw new Exception("Provide an isolated COMPRAS_TEST_CONNECTION seeded with PurchasesSeed.sql.");
        var cfg = new NpgsqlConnectionStringBuilder(Cs);
        if (cfg.Host != "127.0.0.1" || cfg.Port != 55439) throw new Exception("Tests only run on isolated localhost:55439.");
        var supplier = await With(db => Service(db).SaveSupplierAsync(1, null, new SupplierRequest { Name = "Proveedor prueba", Products = [new(1), new(2)] }));
        await Reject(() => With(db => Service(db).SaveSupplierAsync(1, null, new SupplierRequest { Name = "Ajeno", Products = [new(4)] })), "Reject other company's product");
        await Reject(() => With(db => Service(db).SaveSupplierAsync(1, null, new SupplierRequest { Name = "Compuesto", Products = [new(3)] })), "Reject compound as purchased stock item");
        var request = Request(supplier.Id, "001", new(1, 2.5m, 100), new(2, 3, 50));
        var saved = Json(await With(db => Service(db).SaveAsync(1, 1, 2, null, request)));
        int id = saved.GetProperty("Purchase").GetProperty("Id").GetInt32();
        Check(await With(db => db.StockProductos.Where(x => x.IdProducto == 1 && x.IdSucursal == 1).Select(x => x.StockActual).SingleAsync()) == 10, "Draft does not change stock");
        var retry = Json(await With(db => Service(db).SaveAsync(1, 1, 2, null, request)));
        Check(retry.GetProperty("Purchase").GetProperty("Id").GetInt32() == id, "Repeated create returns same draft");
        await Reject(() => With(db => Service(db).SaveAsync(1, 1, 2, null, Request(supplier.Id, "1", new PurchaseItemRequest(1, 1, 100)))), "Reject same document with leading zero variant");
        await Reject(() => With(db => Service(db).GetAsync(2, 3, id)), "Company isolation");
        await Reject(() => With(db => Service(db).GetAsync(1, 2, id)), "Branch isolation");
        request.Version = 1; request.Notes = "Controlar cantidades";
        await With(db => Service(db).SaveAsync(1, 1, 2, id, request));
        await Reject(() => With(db => Service(db).SaveAsync(1, 1, 2, id, request)), "Reject stale draft edit");
        await Reject(() => With(db => Service(db).ControlAsync(1, 1, 1, id, new(1))), "Reject control of stale version");
        // Two independent request contexts contend on the same row.
        await Task.WhenAll(With(db => Service(db).ControlAsync(1, 1, 1, id, new(2))), With(db => Service(db).ControlAsync(1, 1, 1, id, new(2))));
        Check(await With(db => db.StockProductos.Where(x => x.IdProducto == 1 && x.IdSucursal == 1).Select(x => x.StockActual).SingleAsync()) == 12.5m, "Concurrent control increments stock exactly once");
        Check(await With(db => db.StockMovements.CountAsync(x => x.Source == "Compra" && x.ReferenceId == id)) == 2, "Exactly one movement per received product");
        Check(await With(db => db.StockProductos.Where(x => x.IdProducto == 1 && x.IdSucursal == 2).Select(x => x.StockActual).SingleAsync()) == 50, "Other branch stock unchanged");
        var detail = Json(await With(db => Service(db).GetAsync(1, 1, id)));
        var purchase = detail.GetProperty("Purchase");
        Check(purchase.GetProperty("CreatedBy").GetInt32() == 2 && purchase.GetProperty("ControlledBy").GetInt32() == 1, "Server stores distinct loader and controller identities");
        Check(detail.GetProperty("History").GetArrayLength() == 3, "History contains creation, edit, single control");
        var firstSnapshot = JsonDocument.Parse(detail.GetProperty("History")[0].GetProperty("Snapshot").GetString()!);
        Check(firstSnapshot.RootElement.GetProperty("Notes").GetString() == "", "Historical snapshot retains pre-edit values");
        request.Version = 3;
        await Reject(() => With(db => Service(db).SaveAsync(1, 1, 2, id, request)), "Controlled purchase cannot be edited");
        await Reject(() => With(db => Service(db).CancelAsync(1, 1, 1, id, new(3,"Incorrecta"))), "Controlled purchase cannot be annulled without stock reversal");
        var bad = Json(await With(db => Service(db).SaveAsync(1, 1, 2, null, Request(supplier.Id,"2",new(1,5,100),new(2,.5m,50)))));
        int badId = bad.GetProperty("Purchase").GetProperty("Id").GetInt32();
        await Reject(() => With(db => Service(db).ControlAsync(1, 1, 1, badId, new(1))), "Reject fractional quantity of integer-only product");
        Check(await With(db => db.StockProductos.Where(x => x.IdProducto == 1 && x.IdSucursal == 1).Select(x => x.StockActual).SingleAsync()) == 12.5m, "Failure of second item rolls back first stock change");
        Check(await With(db => db.StockMovements.CountAsync(x => x.Source == "Compra" && x.ReferenceId == badId)) == 0, "Failed control leaves no movements");
        Check(await With(db => db.Purchases.Where(x => x.Id == badId).Select(x => x.Status).SingleAsync()) == "Borrador", "Failed control remains draft");
        await With(db => Service(db).CancelAsync(1, 1, 1, badId, new(1,"Error de carga")));
        await Reject(() => With(db => Service(db).ControlAsync(1, 1, 1, badId, new(2))), "Annulled purchase cannot enter stock");
        // Different purchases receive the same product concurrently: no lost update.
        var ids = new List<int>();
        foreach (var n in new[] {"3","4"}) ids.Add(Json(await With(db => Service(db).SaveAsync(1,1,2,null,Request(supplier.Id,n,new PurchaseItemRequest(1,1,100))))).GetProperty("Purchase").GetProperty("Id").GetInt32());
        await Task.WhenAll(ids.Select(i => With(db => Service(db).ControlAsync(1,1,1,i,new(1)))));
        Check(await With(db => db.StockProductos.Where(x => x.IdProducto == 1 && x.IdSucursal == 1).Select(x => x.StockActual).SingleAsync()) == 14.5m, "Concurrent separate purchases preserve both stock increments");
        await using (var db = Db()) {
            var controller = new PurchasesController(Service(db),new(db)) { ControllerContext = new() { HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity(new[]{ new Claim("id_empresa","1"),new Claim("id_sucursal","1"),new Claim(ClaimTypes.NameIdentifier,"2"),new Claim("rol_nombre","EMPLEADO") },"test")) } } };
            Check((await controller.Control(id,new(3)) as ObjectResult)?.StatusCode == 403, "Employee cannot control purchases");
            Check((await controller.NewSupplier(new() { Name="Unauthorized" }) as ObjectResult)?.StatusCode == 403, "Employee cannot edit suppliers");
            Check((await controller.SaveSettings(new() { Name="Unauthorized" }) as ObjectResult)?.StatusCode == 403, "Employee cannot edit company settings");
        }
        var settings = new CompanySettingsRequest { Name="Mi empresa", Phone="12345", Billing=new() { LegalName="Mi empresa SA",Cuit="30-12345678-9",PointOfSale=4 } };
        var settingsResult = Json(await With(db => new CompanySettingsService(db).SaveAsync(1,1,settings)));
        Check(settingsResult.GetProperty("Company").GetProperty("Nombre").GetString()=="Mi empresa", "Company profile is persisted for home/login");
        Check(settingsResult.GetProperty("Billing").GetProperty("PointOfSale").GetInt32()==4, "Billing preparation persists");
        await Reject(() => With(db => new CompanySettingsService(db).SaveAsync(1,1,settings)), "Reject stale company settings save");
        await using(var db=Db()) {
            try { await db.Database.ExecuteSqlRawAsync("UPDATE compra_historial SET motivo='tampered'"); throw new Exception("Audit update should be forbidden"); }
            catch(PostgresException e) when(e.SqlState=="42501") { Console.WriteLine("PASS: API database role cannot rewrite audit history"); }
        }
        Console.WriteLine("Purchase tests passed in isolated PostgreSQL; no shop data changed.");
    }
}
