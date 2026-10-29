using System.Reflection;
using System.Text.Json;
using BarIceCreamShop.Api.Controllers;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

static class SaleVoidRegression
{
    public static async Task Run()
    {
        Check(typeof(SaleVoidsController).GetCustomAttributes<AuthorizeAttribute>().Any(a => a.Policy == SalePermissions.CashierPolicy),
            "Voiding finalized sales requires Admin/Caja authorization");
        var cs = TestConfig.ConnectionString();
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1")) throw new Exception("Only local PostgreSQL may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            var lockId = Random.Shared.Next(1500000000, int.MaxValue);
            await using (var guard = await SaleFiscalLock.AcquireAsync(db, lockId))
                Check(!await db.Database.SqlQueryRaw<bool>($"SELECT pg_try_advisory_xact_lock(73422, {lockId}) AS \"Value\"").SingleAsync(),
                    "Invoice emission and voiding contend on the same per-sale lock");
            Check(await db.Database.SqlQueryRaw<bool>($"SELECT pg_try_advisory_xact_lock(73422, {lockId}) AS \"Value\"").SingleAsync(),
                "The fiscal lock is released when its scope ends");
            // Shadow sale/stock history with temporary tables: no schema privileges needed.
            await db.Database.ExecuteSqlRawAsync("CREATE TEMP TABLE movimientos_stock (LIKE public.movimientos_stock INCLUDING ALL)");
            var sql = File.ReadAllText("../../../Api/dotnet_api/database/add_sale_voids.sql").Replace("BEGIN;", "").Replace("COMMIT;", "")
                .Replace("CREATE TABLE IF NOT EXISTS venta_anulaciones", "CREATE TEMP TABLE venta_anulaciones")
                .Replace("CREATE TABLE IF NOT EXISTS venta_devoluciones", "CREATE TEMP TABLE venta_devoluciones");
            sql = System.Text.RegularExpressions.Regex.Replace(sql, @" REFERENCES \w+\(\w+\)(?: ON DELETE RESTRICT)?", "");
            await db.Database.ExecuteSqlRawAsync(sql);
            var user = await db.Usuarios.AsNoTracking().FirstAsync(u => u.Activo);
            var product = await db.Productos.AsNoTracking().FirstAsync(p => p.IdEmpresa == user.IdEmpresa && p.Activo);
            var sector = await db.Sectors.AsNoTracking().FirstAsync(s => s.IdEmpresa == user.IdEmpresa);
            var company = user.IdEmpresa;
            var branch = new Sucursal { IdEmpresa = company, Nombre = "Anulaciones prueba " + Guid.NewGuid(), Activa = true };
            db.Sucursales.Add(branch); await db.SaveChangesAsync();
            var table = new Table { IdEmpresa = company, IdSucursal = branch.Id, SectorId = sector.Id, Nombre = "Prueba anulación", Number = 1,
                Capacidad = 2, Status = "Ocupada", FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow };
            db.Tables.Add(table); await db.SaveChangesAsync();
            var inventory = new StockProducto { IdProducto = product.Id, IdSucursal = branch.Id, StockActual = 7, FechaModificacion = DateTime.UtcNow };
            db.StockProductos.Add(inventory); await db.SaveChangesAsync();
            var cash = new CajaService(db); var stock = new StockMovementService(db); var service = new SaleVoidService(db, stock);
            var opened = await cash.AbrirAsync(company, branch.Id, user.Id, new(1000, null));
            var nextNumber = (await db.Orders.Where(o => o.IdEmpresa == company).MaxAsync(o => (int?)o.Numero) ?? 0) + 1;
            async Task<Order> Sale(decimal cashAmount = 60, decimal cardAmount = 40)
            {
                var sale = new Order { IdEmpresa = company, IdSucursal = branch.Id, TableId = table.Id, Numero = nextNumber++, UsuarioId = user.Id,
                    Estado = "Finalizada", FechaApertura = DateTime.UtcNow, FechaCierre = DateTime.UtcNow, Subtotal = cashAmount + cardAmount, Total = cashAmount + cardAmount,
                    Items = [new() { ProductId = product.Id, ProductName = product.Nombre, UnitPrice = cashAmount + cardAmount, Quantity = 1,
                        Subtotal = cashAmount + cardAmount, FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow }],
                    Payments = [new() { PaymentTypeName = "Efectivo", Amount = cashAmount, BaseAmount = cashAmount, UsuarioId = user.Id, Fecha = DateTime.UtcNow },
                        new() { PaymentTypeName = "Tarjeta", Amount = cardAmount, BaseAmount = cardAmount, UsuarioId = user.Id, Fecha = DateTime.UtcNow }] };
                db.Orders.Add(sale); await db.SaveChangesAsync(); return sale;
            }
            var sale = await Sale();
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = sale.Version, Reason = "   " }), "Empty reasons are rejected");
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = 99, Reason = "Error de carga" }), "Stale sale versions are rejected");
            await Reject(() => service.VoidAsync(company, branch.Id + 100000, user.Id, sale.Id, new() { Version = sale.Version, Reason = "Error de carga" }), "Another branch cannot void the sale");
            var invoice = new Invoice { CompanyId = company, BranchId = branch.Id, OrderId = sale.Id, Type = 6, PointOfSale = 1, Number = 1,
                Date = DateOnly.FromDateTime(DateTime.UtcNow), Status = "Procesando", UserId = user.Id, CreatedAt = DateTime.UtcNow, Total = 100 };
            db.Invoices.Add(invoice); await db.SaveChangesAsync();
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = sale.Version, Reason = "Error de carga" }), "Pending fiscal invoices block voiding");
            invoice.Status = "Autorizado"; invoice.Cae = "75123456789012";
            invoice.CaeExpiresAt = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)); invoice.AuthorizedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = sale.Version, Reason = "Error de carga" }), "Authorized invoices block voiding");
            invoice.Status = "Rechazado"; invoice.Cae = null; invoice.CaeExpiresAt = null; invoice.AuthorizedAt = null; await db.SaveChangesAsync();
            db.StockMovements.AddRange(
                new StockMovement { CompanyId = company, BranchId = branch.Id, ProductId = product.Id, Type = "Egreso", Quantity = 2, PreviousStock = 10, NewStock = 8,
                    Source = "Compuesto", ReferenceId = sale.Id, Note = "Componente histórico", UserId = user.Id, Date = DateTime.UtcNow },
                new StockMovement { CompanyId = company, BranchId = branch.Id, ProductId = product.Id, Type = "Egreso", Quantity = 1, PreviousStock = 8, NewStock = 7,
                    Source = "Venta", ReferenceId = sale.Id, UserId = user.Id, Date = DateTime.UtcNow });
            await db.SaveChangesAsync();
            var before = await cash.GetActualAsync(company, branch.Id);
            Check(before!.TotalVentas == 100 && before.TotalEfectivoEsperado == 1060, "Cash register includes the original split payments");
            var closeTime = sale.FechaCierre;
            await service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = sale.Version, Reason = "  Cobro duplicado  " });
            Check(sale.Estado == "Cancelada" && sale.FechaCierre == closeTime && table.Status == "Ocupada", "Voiding preserves closing history and does not free a reused table");
            Check(inventory.StockActual == 10 && await db.StockMovements.CountAsync(m => m.ReferenceId == sale.Id && m.Source == "AnulacionVenta") == 1,
                "Stock restoration uses the original simple/component movements and aggregates shared products");
            Check(await db.SalePayments.CountAsync(p => p.OrderId == sale.Id) == 2 && await db.SaleRefunds.CountAsync(r => r.OrderId == sale.Id) == 2,
                "Original payments remain intact and refunds preserve their payment methods");
            var after = await cash.GetActualAsync(company, branch.Id);
            Check(after!.TotalVentas == 0 && after.TotalEfectivoEsperado == 1000 && after.Detalle.All(d => d.Total == 0), "Same-register refunds reverse cash and card totals exactly once");
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, sale.Id, new() { Version = sale.Version, Reason = "Repetida" }), "A repeated request cannot double-refund or double-restock");
            Check((await db.SaleVoids.SingleAsync(v => v.OrderId == sale.Id)).Reason == "Cobro duplicado", "History stores the trimmed mandatory reason and actor");
            var config = new ConfigurationBuilder().Build();
            var systems = new SystemAdminController(db, new(db, new(db)), new(db), config);
            var start = new DateTimeOffset(DateTime.UtcNow.AddDays(-1)); var end = start.AddDays(2);
            var transactions = JsonSerializer.SerializeToElement(((ApiResponse<object>)await systems.Transactions(start, end, company, branch.Id, null, "payments")).Data,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            Check(transactions.GetProperty("amount").GetDecimal() == 0 && transactions.GetProperty("total").GetInt32() == 4, "Systems transaction totals include negative refunds without deleting receipts");
            Check((await new ReportsService(db).SalesDetailAsync(company, branch.Id, new())).Items.Count == 0, "Voided products are excluded from sales reports");

            var oldSale = await Sale(50, 50);
            var closed = await cash.CerrarAsync(company, branch.Id, user.Id, opened.Id, new(null));
            await Reject(() => service.VoidAsync(company, branch.Id, user.Id, oldSale.Id, new() { Version = oldSale.Version, Reason = "Corrección" }), "Voiding requires an open cash register");
            var current = await cash.AbrirAsync(company, branch.Id, user.Id, new(1000, null));
            await service.VoidAsync(company, branch.Id, user.Id, oldSale.Id, new() { Version = oldSale.Version, Reason = "Corrección del turno anterior" });
            var net = await cash.GetActualAsync(company, branch.Id);
            Check(net!.TotalVentas == -100 && net.TotalEfectivoEsperado == 950, "Prior-register refunds are booked in the current register");
            Check((await db.Cajas.AsNoTracking().SingleAsync(c => c.Id == closed.Id)).TotalVentas == closed.TotalVentas && closed.TotalVentas == 100,
                "Previously closed register totals remain unchanged");
            var noStock = await Sale(10, 10);
            await service.VoidAsync(company, branch.Id, user.Id, noStock.Id, new() { Version = noStock.Version, Reason = "Sin stock configurado al vender" });
            Check(inventory.StockActual == 10, "Sales without a stock deduction do not create inventory");
            Console.WriteLine("Sale void checks passed. All test sales, payments, stocks and cash registers will be rolled back.");
        }
        finally { await tx.RollbackAsync(); }
    }
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    static async Task Reject(Func<Task> action, string label) { try { await action(); } catch (SaleException) { Check(true, label); return; } throw new Exception("Expected rejection: " + label); }
}
