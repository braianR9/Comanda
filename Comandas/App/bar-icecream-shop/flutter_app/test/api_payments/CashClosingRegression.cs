using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

static class CashClosingRegression
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
            var user = await db.Usuarios.AsNoTracking().FirstAsync(u => u.Activo);
            var product = await db.Productos.AsNoTracking().FirstAsync(p => p.IdEmpresa == user.IdEmpresa && p.Activo);
            var sector = await db.Sectors.AsNoTracking().FirstAsync(s => s.IdEmpresa == user.IdEmpresa);
            var branch = new Sucursal { IdEmpresa = user.IdEmpresa, Nombre = "Prueba cierre " + Guid.NewGuid(), Activa = true };
            var otherBranch = new Sucursal { IdEmpresa = user.IdEmpresa, Nombre = "Prueba otra caja " + Guid.NewGuid(), Activa = true };
            db.Sucursales.AddRange(branch, otherBranch); await db.SaveChangesAsync();
            var table = new Table { IdEmpresa = user.IdEmpresa, IdSucursal = branch.Id, SectorId = sector.Id,
                Nombre = "Mesa prueba cierre", Number = 1, Capacidad = 2, FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow };
            var counter = new Table { IdEmpresa = user.IdEmpresa, IdSucursal = branch.Id, SectorId = sector.Id,
                Nombre = "Mostrador prueba cierre", Number = 2, Capacidad = 1, EsMostrador = true, FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow };
            db.Tables.AddRange(table, counter); await db.SaveChangesAsync();
            var cash = new CajaService(db);
            var opened = await cash.AbrirAsync(user.IdEmpresa, branch.Id, user.Id, new(0, "Prueba con rollback"));
            var sale = new Order { IdEmpresa = user.IdEmpresa, IdSucursal = branch.Id, TableId = table.Id,
                Numero = (await db.Orders.Where(o => o.IdEmpresa == user.IdEmpresa).MaxAsync(o => (int?)o.Numero) ?? 0) + 1,
                UsuarioId = user.Id, FechaApertura = DateTime.UtcNow, Estado = "EnPedido", Subtotal = 100, Total = 100,
                Items = [new() { ProductId = product.Id, ProductName = product.Nombre, UnitPrice = 100, Quantity = 1,
                    Subtotal = 100, FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow }] };
            db.Orders.Add(sale); await db.SaveChangesAsync();
            foreach (var state in new[] { "Abierta", "EnPedido", "PedidoEnviado", "ConCambios" })
            {
                sale.Estado = state; await db.SaveChangesAsync();
                await Reject(() => cash.CerrarAsync(user.IdEmpresa, branch.Id, user.Id, opened.Id, new(null)), "cuentas pendientes",
                    "Cash closing rejects active state " + state);
            }
            Check((await db.Cajas.AsNoTracking().SingleAsync(c => c.Id == opened.Id)).Estado == "Abierta"
                && !await db.CajaCierreDetalles.AnyAsync(d => d.CajaId == opened.Id),
                "Rejected closing leaves the cash open and writes no closing details");
            sale.TableId = counter.Id; await db.SaveChangesAsync();
            await Reject(() => cash.CerrarAsync(user.IdEmpresa, branch.Id, user.Id, opened.Id, new(null)), counter.Nombre,
                "Pending counter sales also block closing and appear in the error message");
            var other = await cash.AbrirAsync(user.IdEmpresa, otherBranch.Id, user.Id, new(0, null));
            var closedOther = await cash.CerrarAsync(user.IdEmpresa, otherBranch.Id, user.Id, other.Id, new(null));
            Check(closedOther.Estado == "Cerrada", "Pending sales in another branch do not block closing");
            sale.Estado = "Cancelada"; sale.FechaCierre = DateTime.UtcNow; await db.SaveChangesAsync();
            var closed = await cash.CerrarAsync(user.IdEmpresa, branch.Id, user.Id, opened.Id, new(null));
            Check(closed.Estado == "Cerrada", "Cash can close once all accounts are resolved");
            var config = new ConfigurationBuilder().Build();
            var orders = new OrderService(db, config, new(db), cash, new(db), TestConfig.Invoices(db, config));
            await Reject(() => orders.ValidateStockAsync(user.IdEmpresa, branch.Id, [new(product.Id, 1, null)]), "caja abierta",
                "Closed cash prevents adding products to a draft");
            await Reject(() => orders.AddPaymentsAsync(user.IdEmpresa, branch.Id, user.Id, sale.Id,
                new([new(null, 100, null, 1, 100)], sale.Version)), "caja abierta",
                "Closed cash rejects payment registration before writing payments");
            Check(!await db.SalePayments.AnyAsync(p => p.OrderId == sale.Id), "No payment is written when cash is closed");
        }
        finally { await tx.RollbackAsync(); }
        Console.WriteLine("Cash closing checks passed. All fixtures rolled back; existing cash registers and orders were preserved.");
    }
    static void Check(bool condition, string label) { if (!condition) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string message, string label)
    {
        try { await action(); }
        catch (Exception ex) when ((ex is SaleException sale && sale.StatusCode == 409 || ex is CajaException cash && cash.StatusCode == 409)
            && ex.Message.Contains(message, StringComparison.OrdinalIgnoreCase)) { Console.WriteLine("PASS: " + label); return; }
        throw new Exception("Expected rejection: " + label);
    }
}
