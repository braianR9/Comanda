using System.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public partial class PriceListService
{
    public async Task<int> SaveGridAsync(int company, List<PriceCellChange> changes, string user, string reason = "Edición en planilla")
    {
        await using var transaction = context.Database.CurrentTransaction == null
            ? await context.Database.BeginTransactionAsync(IsolationLevel.Serializable) : null;
        var count = await WriteChangesAsync(company, changes, user, reason, Guid.NewGuid());
        if (transaction != null) await transaction.CommitAsync();
        return count;
    }

    private async Task<int> WriteChangesAsync(int company, List<PriceCellChange> changes, string user, string reason, Guid batch)
    {
        if (changes == null || changes.Count is < 1 or > 2000 || changes.Any(c => c == null)) throw new PriceListException("Se permiten entre 1 y 2000 cambios por operación.");
        if (changes.Select(c => (c.IdListaPrecio, c.IdProducto)).Distinct().Count() != changes.Count)
            throw new PriceListException("Hay precios repetidos en la solicitud.");
        if (changes.Any(c => c.PrecioNuevo is < 0 or > 9999999999999999.99m
            || (c.PrecioNuevo.HasValue && decimal.Round(c.PrecioNuevo.Value, 2) != c.PrecioNuevo)))
            throw new PriceListException("Los precios deben ser positivos o cero y tener hasta dos decimales.");
        var listIds = changes.Select(c => c.IdListaPrecio).Distinct().ToList();
        var productIds = changes.Select(c => c.IdProducto).Distinct().ToList();
        var lists = await context.ListasPrecios.Where(l => l.IdEmpresa == company && listIds.Contains(l.Id)).ToListAsync();
        if (lists.Count != listIds.Count || lists.Any(l => !l.Activa))
            throw new PriceListException("Una lista no existe o está inactiva.", 409);
        if (await context.Productos.CountAsync(p => p.IdEmpresa == company && productIds.Contains(p.Id)) != productIds.Count)
            throw new PriceListException("Producto no encontrado.", 404);
        var prices = await context.ProductoPrecios.Where(p => listIds.Contains(p.IdListaPrecio) && productIds.Contains(p.IdProducto))
            .ToDictionaryAsync(p => (p.IdListaPrecio, p.IdProducto));
        foreach (var change in changes)
        {
            prices.TryGetValue((change.IdListaPrecio, change.IdProducto), out var current);
            if (current?.Precio != change.PrecioAnterior)
                throw new PriceListException("Los precios cambiaron desde que abriste la planilla o la vista previa. Recargá y revisá los cambios.", 409);
        }
        await context.Database.ExecuteSqlInterpolatedAsync($"SELECT set_config('app.precio_lote', {batch.ToString()}, true), set_config('app.precio_usuario', {user}, true), set_config('app.precio_motivo', {reason}, true)");
        var now = DateTime.UtcNow;
        var count = 0;
        foreach (var change in changes.Where(c => c.PrecioAnterior != c.PrecioNuevo))
        {
            prices.TryGetValue((change.IdListaPrecio, change.IdProducto), out var current);
            if (change.PrecioNuevo == null)
            {
                if (current != null) context.ProductoPrecios.Remove(current);
            }
            else if (current == null)
                context.ProductoPrecios.Add(new ProductoPrecio { IdListaPrecio = change.IdListaPrecio,
                    IdProducto = change.IdProducto, Precio = change.PrecioNuevo.Value, FechaModificacion = now });
            else { current.Precio = change.PrecioNuevo.Value; current.FechaModificacion = now; }
            lists.Single(l => l.Id == change.IdListaPrecio).FechaModificacion = now;
            count++;
        }
        await context.SaveChangesAsync();
        return count;
    }

    public async Task<object> HistoryAsync(int company, int page)
    {
        page = Math.Max(1, page);
        var query = context.PriceHistory.AsNoTracking().Where(h => h.IdEmpresa == company);
        var batches = query.GroupBy(h => h.Lote).Select(g => new {
            Lote = g.Key, Fecha = g.Max(h => h.Fecha), Usuario = g.Max(h => h.Usuario),
            Motivo = g.Max(h => h.Motivo), Cantidad = g.Count(), Revertido = g.Any(h => h.RevertidoPor != null)
        });
        return new { items = await batches.OrderByDescending(h => h.Fecha).Skip((page - 1) * 20).Take(20).ToListAsync(),
            page, totalPages = (int)Math.Ceiling(await batches.CountAsync() / 20.0) };
    }

    public async Task<List<PriceHistory>> HistoryDetailsAsync(int company, Guid batch) =>
        await context.PriceHistory.AsNoTracking().Where(h => h.IdEmpresa == company && h.Lote == batch).OrderBy(h => h.Id).ToListAsync();

    public async Task<int> RevertAsync(int company, Guid batch, string user)
    {
        await using var transaction = context.Database.CurrentTransaction == null
            ? await context.Database.BeginTransactionAsync(IsolationLevel.Serializable) : null;
        var history = await context.PriceHistory.Where(h => h.IdEmpresa == company && h.Lote == batch).ToListAsync();
        if (history.Count == 0) throw new PriceListException("Cambio no encontrado.", 404);
        if (history.Any(h => h.RevertidoPor != null || h.Motivo.StartsWith("Reversión")))
            throw new PriceListException("Este cambio ya fue revertido o es una reversión.", 409);
        var listIds = history.Select(h => h.IdListaPrecio).Distinct().ToList();
        var productIds = history.Select(h => h.IdProducto).Distinct().ToList();
        var latest = await context.PriceHistory.Where(h => h.IdEmpresa == company && listIds.Contains(h.IdListaPrecio) && productIds.Contains(h.IdProducto))
            .GroupBy(h => new { h.IdListaPrecio, h.IdProducto }).Select(g => new { g.Key, Id = g.Max(h => h.Id) }).ToListAsync();
        if (history.Any(h => latest.Single(x => x.Key.IdListaPrecio == h.IdListaPrecio && x.Key.IdProducto == h.IdProducto).Id != h.Id))
            throw new PriceListException("Hay cambios posteriores en estos precios. No se puede revertir este grupo sin sobrescribirlos.", 409);
        var reversal = Guid.NewGuid();
        var changes = history.Select(h => new PriceCellChange { IdListaPrecio = h.IdListaPrecio, IdProducto = h.IdProducto,
            PrecioAnterior = h.PrecioNuevo, PrecioNuevo = h.PrecioAnterior }).ToList();
        var count = await WriteChangesAsync(company, changes, user, $"Reversión de {batch}", reversal);
        foreach (var item in history) item.RevertidoPor = reversal;
        await context.SaveChangesAsync();
        if (transaction != null) await transaction.CommitAsync();
        return count;
    }
}
