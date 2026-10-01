using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

/// Calendar rules use the same Argentina business time (UTC-3) as reports.
public static class ScheduledPriceCalculator
{
    public static bool IsActiveAt(ScheduledPriceRule rule, DateTimeOffset instant)
    {
        if (!rule.Activa) return false;
        var local = instant.ToOffset(TimeSpan.FromHours(-3));
        var day = DateOnly.FromDateTime(local.DateTime);
        var minute = local.Hour * 60 + local.Minute;
        if (rule.MinutoDesde.HasValue && rule.MinutoHasta.HasValue)
        {
            var start = rule.MinutoDesde.Value;
            var end = rule.MinutoHasta.Value;
            if (start < end)
            {
                if (minute < start || minute >= end) return false;
            }
            else
            {
                if (minute >= start) { /* This occurrence starts today. */ }
                else if (minute < end) day = day.AddDays(-1);
                else return false;
            }
        }
        var weekday = ((int)day.DayOfWeek + 6) % 7; // bit 0 = Monday
        return day >= rule.FechaDesde && (!rule.FechaHasta.HasValue || day <= rule.FechaHasta.Value)
            && (rule.DiasSemana & (1 << weekday)) != 0;
    }

    public static ScheduledPriceRule? Select(IEnumerable<ScheduledPriceRule> rules, Producto product, DateTimeOffset instant) =>
        rules.Where(r => IsActiveAt(r, instant)
            && (!r.IdProducto.HasValue || r.IdProducto == product.Id)
            && (!r.IdRubro.HasValue || r.IdRubro == product.IdRubro)
            && (!r.IdSubRubro.HasValue || r.IdSubRubro == product.IdSubRubro))
        .OrderByDescending(r => r.Prioridad)
        .ThenByDescending(r => r.IdProducto.HasValue ? 3 : r.IdSubRubro.HasValue ? 2 : r.IdRubro.HasValue ? 1 : 0)
        .ThenBy(r => r.Id).FirstOrDefault();

    public static decimal Calculate(decimal basePrice, ScheduledPriceRule rule) => PriceListService.CalculatePrice(
        rule.Operacion == "PrecioFijo" ? rule.Valor : basePrice,
        new BulkPriceOperationRequest { Operacion = rule.Operacion == "PrecioFijo" ? "AumentarImporte" : rule.Operacion,
            Valor = rule.Operacion == "PrecioFijo" ? 0 : rule.Valor, Redondeo = rule.Redondeo, ModoRedondeo = rule.ModoRedondeo });
}

public partial class PriceListService
{
    // Scoped service: all products in one request are evaluated at the same instant.
    private readonly DateTimeOffset priceQueryInstant = DateTimeOffset.UtcNow;
    public async Task<List<ScheduledPriceRule>> RulesAsync(int company, int listId)
    {
        await RequireAsync(company, listId);
        return await context.ScheduledPriceRules.AsNoTracking().Where(r => r.IdEmpresa == company && r.IdListaPrecio == listId)
            .OrderByDescending(r => r.Activa).ThenByDescending(r => r.Prioridad).ThenBy(r => r.Id).ToListAsync();
    }

    public async Task<ScheduledPriceRule> SaveRuleAsync(int company, int listId, int? id, SaveScheduledPriceRuleRequest request, string user)
    {
        await RequireAsync(company, listId);
        if (string.IsNullOrWhiteSpace(request.Nombre) || request.Nombre.Trim().Length > 150)
            throw new PriceListException("Ingresá un nombre de hasta 150 caracteres.");
        if (request.FechaDesde == default || request.FechaHasta < request.FechaDesde)
            throw new PriceListException("El rango de fechas no es válido.");
        if (request.DiasSemana is < 1 or > 127) throw new PriceListException("Seleccioná al menos un día.");
        if (request.Prioridad is < 0 or > 10000) throw new PriceListException("La prioridad debe estar entre 0 y 10000.");
        if (request.MinutoDesde.HasValue != request.MinutoHasta.HasValue
            || request.MinutoDesde is < 0 or > 1439 || request.MinutoHasta is < 0 or > 1439
            || (request.MinutoDesde.HasValue && request.MinutoDesde == request.MinutoHasta))
            throw new PriceListException("Indicá ambos horarios y usá horas distintas, o elegí todo el día.");
        if (request.Valor < 0 || request.Valor > 9999999999999999.99m || decimal.Round(request.Valor, 2) != request.Valor)
            throw new PriceListException("El valor debe ser positivo o cero y tener hasta dos decimales.");
        if (new[] { request.IdProducto, request.IdRubro, request.IdSubRubro }.Count(v => v.HasValue) > 1)
            throw new PriceListException("Elegí un único alcance: producto, rubro, subrubro o toda la lista.");
        if (request.IdProducto.HasValue && !await context.Productos.AnyAsync(p => p.IdEmpresa == company && p.Id == request.IdProducto))
            throw new PriceListException("Producto no encontrado.", 404);
        if (request.IdRubro.HasValue && !await context.Rubros.AnyAsync(p => p.IdEmpresa == company && p.Id == request.IdRubro))
            throw new PriceListException("Rubro no encontrado.", 404);
        if (request.IdSubRubro.HasValue && !await context.SubRubros.AnyAsync(p => p.IdEmpresa == company && p.Id == request.IdSubRubro))
            throw new PriceListException("Subrubro no encontrado.", 404);
        // Validate arithmetic and rounding even for rules that are not active yet.
        ScheduledPriceCalculator.Calculate(0, new ScheduledPriceRule { Operacion = request.Operacion, Valor = request.Valor,
            Redondeo = request.Redondeo, ModoRedondeo = request.ModoRedondeo });
        var rule = id.HasValue ? await context.ScheduledPriceRules.SingleOrDefaultAsync(r => r.Id == id && r.IdEmpresa == company && r.IdListaPrecio == listId)
            ?? throw new PriceListException("Regla no encontrada.", 404) : new ScheduledPriceRule { IdEmpresa = company, IdListaPrecio = listId };
        if (id.HasValue && rule.Version != request.Version)
            throw new PriceListException("La regla cambió. Recargá antes de editarla.", 409);
        rule.Nombre = request.Nombre.Trim(); rule.Activa = request.Activa; rule.Prioridad = request.Prioridad;
        rule.IdProducto = request.IdProducto; rule.IdRubro = request.IdRubro; rule.IdSubRubro = request.IdSubRubro;
        rule.FechaDesde = request.FechaDesde; rule.FechaHasta = request.FechaHasta; rule.DiasSemana = request.DiasSemana;
        rule.MinutoDesde = request.MinutoDesde; rule.MinutoHasta = request.MinutoHasta;
        rule.Operacion = request.Operacion; rule.Valor = request.Valor; rule.Redondeo = request.Redondeo; rule.ModoRedondeo = request.ModoRedondeo;
        rule.Usuario = user; rule.FechaModificacion = DateTime.UtcNow;
        if (id.HasValue) rule.Version++; else context.ScheduledPriceRules.Add(rule);
        try { await context.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) { throw new PriceListException("La regla cambió. Recargá antes de editarla.", 409); }
        return rule;
    }

    public async Task<List<EffectivePriceDto>> QuotePricesAsync(int company, int branch, PriceQuoteRequest request)
    {
        if (request.ProductoIds == null || request.ProductoIds.Count is < 1 or > 100 || request.ProductoIds.Any(id => id <= 0))
            throw new PriceListException("Consultá entre 1 y 100 productos válidos.");
        var listId = await ResolveSaleListIdAsync(company, branch, request.IdListaPrecio);
        return await QuoteListAsync(company, listId, request.ProductoIds.Distinct().ToList(), request.Fecha ?? priceQueryInstant);
    }

    private async Task<List<EffectivePriceDto>> QuoteListAsync(int company, int listId, List<int> ids, DateTimeOffset instant)
    {
        var list = await RequireAsync(company, listId);
        if (!list.Activa) throw new PriceListException("La lista de precios está inactiva.", 409);
        var products = await context.Productos.AsNoTracking().Where(p => p.IdEmpresa == company && p.Activo && ids.Contains(p.Id)).ToListAsync();
        if (products.Count != ids.Count) throw new PriceListException("Un producto no existe o está inactivo.", 404);
        var prices = await context.ProductoPrecios.AsNoTracking().Where(p => p.IdListaPrecio == listId && ids.Contains(p.IdProducto))
            .ToDictionaryAsync(p => p.IdProducto, p => p.Precio);
        var rules = await context.ScheduledPriceRules.AsNoTracking().Where(r => r.IdEmpresa == company && r.IdListaPrecio == listId && r.Activa).ToListAsync();
        return products.Select(p => {
            decimal? basePrice = prices.TryGetValue(p.Id, out var price) ? price : null;
            var rule = basePrice.HasValue ? ScheduledPriceCalculator.Select(rules, p, instant) : null;
            return new EffectivePriceDto(p.Id, listId, list.Nombre, basePrice,
                rule == null ? basePrice : ScheduledPriceCalculator.Calculate(basePrice!.Value, rule), rule?.Id, rule?.Nombre, instant);
        }).ToList();
    }

    public async Task<decimal?> ResolvePriceAsync(int productId, int listId, DateTimeOffset? instant = null)
    {
        var company = await context.ListasPrecios.AsNoTracking().Where(l => l.Id == listId).Select(l => (int?)l.IdEmpresa).SingleOrDefaultAsync()
            ?? throw new PriceListException("Lista no encontrada.", 404);
        return (await QuoteListAsync(company, listId, [productId], instant ?? priceQueryInstant)).Single().PrecioFinal;
    }
}
