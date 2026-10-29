using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class SaleVoidService(AppDbContext db, StockMovementService stock)
{
    public async Task<object> VoidAsync(int company, int branch, int user, int id, VoidSaleRequest request)
    {
        var reason = request.Reason?.Trim() ?? "";
        if (reason.Length is < 3 or > 500) throw new SaleException("Indicá un motivo de entre 3 y 500 caracteres.");
        if (request.Version < 1) throw new SaleException("Actualizá la venta antes de anular.", 409);
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(73422, {id})");
        // Mismo bloqueo de caja que usan el cierre y los cobros.
        var cash = await db.Cajas.FromSqlInterpolated(
            $"SELECT * FROM cajas WHERE id_empresa={company} AND id_sucursal={branch} AND estado='Abierta' FOR UPDATE")
            .SingleOrDefaultAsync() ?? throw new SaleException("Abrí la caja para registrar la devolución de la venta.", 409);
        var sale = await db.Orders.FromSqlInterpolated(
            $"SELECT * FROM ventas WHERE id_venta={id} AND id_empresa={company} AND id_sucursal={branch} FOR UPDATE")
            .Include(s => s.Payments).SingleOrDefaultAsync() ?? throw new SaleException("Venta no encontrada.", 404);
        if (sale.Estado != "Finalizada" || await db.SaleVoids.AnyAsync(v => v.OrderId == id))
            throw new SaleException("Solo se pueden anular ventas finalizadas que no estén anuladas.", 409);
        if (sale.Version != request.Version) throw new SaleException("La venta cambió. Actualizá antes de anular.", 409);
        if (await db.Invoices.AnyAsync(i => i.OrderId == id && i.Status != "Rechazado"))
            throw new SaleException("La venta tiene un comprobante fiscal o un intento pendiente. Revisalo en Comprobantes antes de continuar.", 409);
        var total = sale.Payments.Sum(p => p.Amount);
        if (total != sale.Total) throw new SaleException("Los pagos registrados no coinciden con el total. Revisá la venta antes de anularla.", 409);
        var now = DateTime.UtcNow;
        db.SaleVoids.Add(new SaleVoid { OrderId = id, CompanyId = company, BranchId = branch, CashId = cash.Id,
            UserId = user, Date = now, Reason = reason, Refunded = total });
        foreach (var payment in sale.Payments.Where(p => p.Amount > 0))
            db.SaleRefunds.Add(new SaleRefund { OrderId = id, OriginalPaymentId = payment.Id,
                PaymentTypeName = payment.PaymentTypeName, Amount = payment.Amount });
        await stock.ReverseSaleAsync(company, branch, user, id, reason);
        sale.Estado = "Cancelada";
        sale.Version++;
        // La fecha de cobro, los productos, los pagos y las mesas actuales se conservan.
        foreach (var job in await db.GoogleSheetJobs.Where(j => j.OrderId == id && j.Status == "Pendiente").ToListAsync())
            job.Status = "Cancelado";
        db.SystemEvents.Add(new SystemEvent { Type = "Audit", Level = "Information", Source = "Ventas",
            Message = $"Venta {sale.Numero} anulada: {reason}", CompanyId = company, BranchId = branch, UserId = user,
            Detail = System.Text.Json.JsonSerializer.Serialize(new { saleId = id, cashId = cash.Id, refunded = total, stockRestored = true }) });
        await db.SaveChangesAsync();
        if (tx != null) await tx.CommitAsync();
        return new { saleId = id, status = sale.Estado, at = now, reason, refunded = total, version = sale.Version };
    }

    public async Task<object> ListAsync(int company, int branch, int page)
    {
        page = Math.Clamp(page, 1, 100000); const int size = 50;
        var query = from v in db.SaleVoids.AsNoTracking()
            join s in db.Orders on v.OrderId equals s.Id
            join u in db.Usuarios on v.UserId equals u.Id
            where v.CompanyId == company && v.BranchId == branch
            select new { saleId = s.Id, saleNumber = s.Numero, closedAt = s.FechaCierre, at = v.Date,
                reason = v.Reason, refunded = v.Refunded, userName = u.Nombre + " " + u.Apellido,
                table = s.Table.Nombre, v.CashId };
        var total = await query.CountAsync();
        var items = await query.OrderByDescending(v => v.at).ThenByDescending(v => v.saleId)
            .Skip((page - 1) * size).Take(size).ToListAsync();
        return new { page, totalPages = (int)Math.Ceiling(total / (double)size), totalItems = total, items };
    }
}
