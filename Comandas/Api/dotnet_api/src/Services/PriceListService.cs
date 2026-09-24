using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class PriceListException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class PriceListService(AppDbContext context)
{
    private static readonly string[] Operaciones =
        ["AumentarPorcentaje", "DisminuirPorcentaje", "AumentarImporte", "DisminuirImporte"];

    public async Task<List<PriceListDto>> ListAsync(int company) =>
        await context.ListasPrecios.AsNoTracking().Where(l => l.IdEmpresa == company)
            .OrderByDescending(l => l.EsPredeterminada).ThenBy(l => l.Nombre)
            .Select(l => new PriceListDto(l.Id, l.Nombre, l.EsPredeterminada, l.Activa, l.FechaCreacion, l.FechaModificacion,
                context.ProductoPrecios.Count(p => p.IdListaPrecio == l.Id)))
            .ToListAsync();

    public async Task<PriceListDto> CreateAsync(int company, CreatePriceListRequest request)
    {
        var nombre = (request.Nombre ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(nombre)) throw new PriceListException("El nombre es obligatorio.");
        if (await context.ListasPrecios.AnyAsync(l => l.IdEmpresa == company && l.Nombre.ToLower() == nombre.ToLower()))
            throw new PriceListException("Ya existe una lista con ese nombre.", 409);

        ListaPrecio? origen = null;
        if (request.CopiarDesdeListaId.HasValue)
            origen = await RequireAsync(company, request.CopiarDesdeListaId.Value);

        var now = DateTime.UtcNow;
        var lista = new ListaPrecio { IdEmpresa = company, Nombre = nombre, EsPredeterminada = false, Activa = true, FechaCreacion = now, FechaModificacion = now };
        context.ListasPrecios.Add(lista);
        await context.SaveChangesAsync();

        if (origen != null)
        {
            await context.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO producto_precios (id_producto, id_lista_precio, precio, fecha_modificacion)
                SELECT id_producto, {lista.Id}, precio, {now}
                FROM producto_precios WHERE id_lista_precio = {origen.Id}
                """);
        }

        return await ToDtoAsync(lista);
    }

    public async Task<PriceListDto> RenameAsync(int company, int id, UpdatePriceListRequest request)
    {
        var nombre = (request.Nombre ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(nombre)) throw new PriceListException("El nombre es obligatorio.");
        var lista = await RequireAsync(company, id);
        if (await context.ListasPrecios.AnyAsync(l => l.IdEmpresa == company && l.Id != id && l.Nombre.ToLower() == nombre.ToLower()))
            throw new PriceListException("Ya existe una lista con ese nombre.", 409);
        lista.Nombre = nombre; lista.FechaModificacion = DateTime.UtcNow;
        await context.SaveChangesAsync();
        return await ToDtoAsync(lista);
    }

    public async Task<PriceListDto> SetActiveAsync(int company, int id, bool activa)
    {
        var lista = await RequireAsync(company, id);
        if (!activa && lista.EsPredeterminada)
            throw new PriceListException("No podés desactivar la lista predeterminada.", 409);
        lista.Activa = activa; lista.FechaModificacion = DateTime.UtcNow;
        await context.SaveChangesAsync();
        return await ToDtoAsync(lista);
    }

    public async Task<PriceListDto> SetDefaultAsync(int company, int id)
    {
        var lista = await RequireAsync(company, id);
        if (!lista.Activa) throw new PriceListException("Una lista inactiva no puede ser la predeterminada.", 409);
        var actual = await context.ListasPrecios.Where(l => l.IdEmpresa == company && l.EsPredeterminada).ToListAsync();
        foreach (var item in actual) { item.EsPredeterminada = false; item.FechaModificacion = DateTime.UtcNow; }
        lista.EsPredeterminada = true; lista.FechaModificacion = DateTime.UtcNow;
        await context.SaveChangesAsync();
        return await ToDtoAsync(lista);
    }

    public async Task DeleteAsync(int company, int id)
    {
        var lista = await RequireAsync(company, id);
        if (lista.EsPredeterminada) throw new PriceListException("No podés eliminar la lista predeterminada.", 409);
        var usadaEnVentas = await context.Orders.AnyAsync(o => o.IdListaPrecio == id)
            || await context.Set<OrderItem>().AnyAsync(i => i.IdListaPrecio == id);
        if (usadaEnVentas)
            throw new PriceListException("No se puede eliminar: la lista ya fue utilizada en ventas históricas. Desactivala en su lugar.", 409);
        await context.Sucursales.Where(s => s.IdListaPrecioPredeterminada == id)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.IdListaPrecioPredeterminada, x => null));
        context.ListasPrecios.Remove(lista);
        try { await context.SaveChangesAsync(); }
        catch (DbUpdateException) { throw new PriceListException("No se puede eliminar: la lista tiene información asociada.", 409); }
    }

    public async Task<PagedResult<ProductPriceDto>> GetPricesAsync(
        int company, int listId, int? idRubro, int? idSubRubro, string? texto, int page, int pageSize)
    {
        await RequireAsync(company, listId);
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var query = FilterProducts(company, idRubro, idSubRubro, texto, null);

        var total = await query.CountAsync();
        var items = await query.OrderBy(p => p.Nombre)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(p => new
            {
                p.Id, p.Codigo, p.Nombre,
                Rubro = new ReferenciaDto(p.Rubro.Id, p.Rubro.Nombre),
                SubRubro = p.SubRubro == null ? null : new ReferenciaDto(p.SubRubro.Id, p.SubRubro.Nombre),
                Precio = context.ProductoPrecios.Where(pp => pp.IdProducto == p.Id && pp.IdListaPrecio == listId).Select(pp => (decimal?)pp.Precio).SingleOrDefault(),
            }).ToListAsync();

        return new PagedResult<ProductPriceDto>
        {
            Items = items.Select(x => new ProductPriceDto(x.Id, x.Codigo, x.Nombre, x.Rubro, x.SubRubro, x.Precio)).ToList(),
            Page = page, PageSize = pageSize, TotalItems = total,
            TotalPages = (int)Math.Ceiling(total / (double)pageSize),
        };
    }

    public async Task<ProductPriceDto> SetPriceAsync(int company, int listId, int productId, decimal precio)
    {
        if (precio < 0) throw new PriceListException("El precio no puede ser negativo.");
        await RequireAsync(company, listId);
        var producto = await context.Productos.AsNoTracking()
            .Include(p => p.Rubro).Include(p => p.SubRubro)
            .FirstOrDefaultAsync(p => p.Id == productId && p.IdEmpresa == company)
            ?? throw new PriceListException("Producto no encontrado.", 404);

        var now = DateTime.UtcNow;
        var existing = await context.ProductoPrecios.FirstOrDefaultAsync(pp => pp.IdProducto == productId && pp.IdListaPrecio == listId);
        if (existing == null)
            context.ProductoPrecios.Add(new ProductoPrecio { IdProducto = productId, IdListaPrecio = listId, Precio = decimal.Round(precio, 2), FechaModificacion = now });
        else
        { existing.Precio = decimal.Round(precio, 2); existing.FechaModificacion = now; }
        await context.SaveChangesAsync();

        return new ProductPriceDto(producto.Id, producto.Codigo, producto.Nombre,
            new ReferenciaDto(producto.Rubro.Id, producto.Rubro.Nombre),
            producto.SubRubro == null ? null : new ReferenciaDto(producto.SubRubro.Id, producto.SubRubro.Nombre),
            decimal.Round(precio, 2));
    }

    public async Task<List<BulkPricePreviewItem>> PreviewBulkAsync(int company, int listId, BulkPriceOperationRequest request)
    {
        await RequireAsync(company, listId);
        ValidateOperation(request);
        var filtro = request.Filtro ?? new BulkPriceFilter();
        var productos = await FilterProducts(company, filtro.IdRubro, filtro.IdSubRubro, filtro.Texto, filtro.ProductoIds)
            .Select(p => new { p.Id, p.Nombre }).ToListAsync();
        var precios = await context.ProductoPrecios.AsNoTracking()
            .Where(pp => pp.IdListaPrecio == listId && productos.Select(x => x.Id).Contains(pp.IdProducto))
            .ToDictionaryAsync(pp => pp.IdProducto, pp => pp.Precio);

        // Los productos sin precio configurado en esta lista se excluyen: no hay una base sobre la cual calcular el aumento/descuento.
        return productos.Where(p => precios.ContainsKey(p.Id))
            .Select(p => new BulkPricePreviewItem(p.Id, p.Nombre, precios[p.Id], ApplyOperation(precios[p.Id], request.Operacion, request.Valor)))
            .OrderBy(x => x.Nombre).ToList();
    }

    public async Task<int> ApplyBulkAsync(int company, int listId, BulkPriceOperationRequest request)
    {
        var preview = await PreviewBulkAsync(company, listId, request);
        var now = DateTime.UtcNow;
        var existentes = await context.ProductoPrecios
            .Where(pp => pp.IdListaPrecio == listId && preview.Select(x => x.IdProducto).Contains(pp.IdProducto))
            .ToDictionaryAsync(pp => pp.IdProducto);
        foreach (var item in preview)
        {
            existentes[item.IdProducto].Precio = item.PrecioNuevo;
            existentes[item.IdProducto].FechaModificacion = now;
        }
        await context.SaveChangesAsync();
        return preview.Count;
    }

    public async Task<int> GetDefaultListIdAsync(int company)
    {
        var id = await context.ListasPrecios.AsNoTracking()
            .Where(l => l.IdEmpresa == company && l.EsPredeterminada).Select(l => (int?)l.Id).FirstOrDefaultAsync();
        if (id.HasValue) return id.Value;
        // Red de seguridad: en circunstancias normales el trigger de la base ya la crea.
        var now = DateTime.UtcNow;
        var lista = new ListaPrecio { IdEmpresa = company, Nombre = "General", EsPredeterminada = true, Activa = true, FechaCreacion = now, FechaModificacion = now };
        context.ListasPrecios.Add(lista);
        await context.SaveChangesAsync();
        return lista.Id;
    }

    public async Task<int> ResolveSaleListIdAsync(int company, int branch, int? requested)
    {
        if (requested.HasValue)
        {
            var ok = await context.ListasPrecios.AnyAsync(l => l.Id == requested && l.IdEmpresa == company && l.Activa);
            if (!ok) throw new PriceListException("La lista de precios indicada no existe o está inactiva.", 404);
            return requested.Value;
        }
        var branchDefault = await context.Sucursales.AsNoTracking()
            .Where(s => s.Id == branch && s.IdEmpresa == company).Select(s => s.IdListaPrecioPredeterminada).FirstOrDefaultAsync();
        if (branchDefault.HasValue && await context.ListasPrecios.AnyAsync(l => l.Id == branchDefault && l.Activa))
            return branchDefault.Value;
        return await GetDefaultListIdAsync(company);
    }

    public async Task<decimal?> ResolvePriceAsync(int productId, int listId) =>
        await context.ProductoPrecios.AsNoTracking()
            .Where(pp => pp.IdProducto == productId && pp.IdListaPrecio == listId)
            .Select(pp => (decimal?)pp.Precio).FirstOrDefaultAsync();

    /// Mantiene sincronizado el precio "simple" del producto (lista predeterminada de la empresa)
    /// para que el alta/edición común de un producto siga sintiéndose como Producto → Precio.
    public async Task SetDefaultListPriceAsync(int company, int productId, decimal precio)
    {
        var listId = await GetDefaultListIdAsync(company);
        var now = DateTime.UtcNow;
        var existing = await context.ProductoPrecios.FirstOrDefaultAsync(pp => pp.IdProducto == productId && pp.IdListaPrecio == listId);
        if (existing == null)
            context.ProductoPrecios.Add(new ProductoPrecio { IdProducto = productId, IdListaPrecio = listId, Precio = decimal.Round(precio, 2), FechaModificacion = now });
        else
        { existing.Precio = decimal.Round(precio, 2); existing.FechaModificacion = now; }
        await context.SaveChangesAsync();
    }

    private async Task<ListaPrecio> RequireAsync(int company, int id) =>
        await context.ListasPrecios.FirstOrDefaultAsync(l => l.Id == id && l.IdEmpresa == company)
        ?? throw new PriceListException("Lista de precios no encontrada.", 404);

    private async Task<PriceListDto> ToDtoAsync(ListaPrecio lista) => new(
        lista.Id, lista.Nombre, lista.EsPredeterminada, lista.Activa, lista.FechaCreacion, lista.FechaModificacion,
        await context.ProductoPrecios.CountAsync(p => p.IdListaPrecio == lista.Id));

    private IQueryable<Producto> FilterProducts(int company, int? idRubro, int? idSubRubro, string? texto, List<int>? ids)
    {
        var query = context.Productos.AsNoTracking().Include(p => p.Rubro).Include(p => p.SubRubro)
            .Where(p => p.IdEmpresa == company && p.Activo);
        if (idRubro.HasValue) query = query.Where(p => p.IdRubro == idRubro);
        if (idSubRubro.HasValue) query = query.Where(p => p.IdSubRubro == idSubRubro);
        if (ids is { Count: > 0 }) query = query.Where(p => ids.Contains(p.Id));
        if (!string.IsNullOrWhiteSpace(texto))
        {
            var term = texto.Trim();
            query = int.TryParse(term, out var codigo)
                ? query.Where(p => p.Codigo == codigo || EF.Functions.ILike(p.Nombre, $"%{term}%"))
                : query.Where(p => EF.Functions.ILike(p.Nombre, $"%{term}%"));
        }
        return query;
    }

    private static void ValidateOperation(BulkPriceOperationRequest request)
    {
        if (!Operaciones.Contains(request.Operacion))
            throw new PriceListException("La operación debe ser AumentarPorcentaje, DisminuirPorcentaje, AumentarImporte o DisminuirImporte.");
        if (request.Valor < 0) throw new PriceListException("El valor no puede ser negativo.");
        if (request.Operacion.Contains("Porcentaje") && request.Valor > 100)
            throw new PriceListException("El porcentaje no puede superar 100.");
    }

    private static decimal ApplyOperation(decimal actual, string operacion, decimal valor) => decimal.Round(operacion switch
    {
        "AumentarPorcentaje" => actual * (1 + valor / 100),
        "DisminuirPorcentaje" => Math.Max(0, actual * (1 - valor / 100)),
        "AumentarImporte" => actual + valor,
        "DisminuirImporte" => Math.Max(0, actual - valor),
        _ => actual,
    }, 2, MidpointRounding.AwayFromZero);
}
