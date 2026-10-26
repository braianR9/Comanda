using System.Data;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace BarIceCreamShop.Api.Services;

public sealed class ProductoException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class ProductoService
{
    private readonly AppDbContext _context;
    private readonly PriceListService _priceLists;

    public ProductoService(AppDbContext context, PriceListService priceLists)
    {
        _context = context;
        _priceLists = priceLists;
    }

    public async Task<PagedResult<ProductListDto>> GetAllAsync(
        int idEmpresa, string? texto, int? idRubro, int? idSubRubro,
        bool? activo, int page, int pageSize, string? orden = null)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var query = _context.Productos.AsNoTracking()
            .Where(p => p.IdEmpresa == idEmpresa);

        query = activo.HasValue ? query.Where(p => p.Activo == activo) : query.Where(p => p.Activo);
        if (idRubro.HasValue) query = query.Where(p => p.IdRubro == idRubro);
        if (idSubRubro.HasValue) query = query.Where(p => p.IdSubRubro == idSubRubro);
        if (!string.IsNullOrWhiteSpace(texto))
        {
            var term = texto.Trim();
            query = int.TryParse(term, out var codigo)
                ? query.Where(p => p.Codigo == codigo || EF.Functions.ILike(p.Nombre, $"%{term}%"))
                : query.Where(p => EF.Functions.ILike(p.Nombre, $"%{term}%"));
        }

        var total = await query.CountAsync();
        // "vendidos": más vendidos primero (unidades en ventas no canceladas), para la selección rápida en el salón.
        var ordered = string.Equals(orden, "vendidos", StringComparison.OrdinalIgnoreCase)
            ? query.OrderByDescending(p => _context.Orders
                    .Where(o => o.IdEmpresa == idEmpresa && o.Estado != "Cancelada")
                    .SelectMany(o => o.Items)
                    .Where(i => i.ProductId == p.Id && i.Estado == "Activo")
                    .Sum(i => (decimal?)i.Quantity) ?? 0)
                .ThenBy(p => p.Orden).ThenBy(p => p.Nombre)
            : query.OrderBy(p => p.Orden).ThenBy(p => p.Nombre);
        var items = await ordered.ThenBy(p => p.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(p => new ProductListDto
            {
                Id = p.Id, Codigo = p.Codigo, CodigoBarras = p.CodigoBarras, Nombre = p.Nombre,
                TipoProducto = p.TipoProducto,
                Rubro = new ReferenciaDto(p.Rubro.Id, p.Rubro.Nombre),
                SubRubro = p.SubRubro == null ? null : new ReferenciaDto(p.SubRubro.Id, p.SubRubro.Nombre),
                PrecioConIva = p.PrecioConIva, ImagenUrl = p.ImagenUrl, Activo = p.Activo
            }).ToListAsync();

        return new PagedResult<ProductListDto>
        {
            Items = items, Page = page, PageSize = pageSize, TotalItems = total,
            TotalPages = (int)Math.Ceiling(total / (double)pageSize)
        };
    }

    public async Task<ProductDetailDto?> GetAsync(int idEmpresa, int id, int? idSucursal = null)
    {
        var product = await _context.Productos.AsNoTracking()
            .Include(p => p.Rubro).Include(p => p.SubRubro).Include(p => p.Alicuota)
            .FirstOrDefaultAsync(p => p.IdEmpresa == idEmpresa && p.Id == id);
        if (product == null) return null;
        var detail = ToDetail(product);
        detail.Componentes = await new StockMovementService(_context).ComponentsAsync(idEmpresa, id);
        if (idSucursal.HasValue) detail.Stock = await GetStockValueAsync(id, idSucursal.Value);
        return detail;
    }

    public async Task<ProductDetailDto> CreateAsync(int idEmpresa, int idSucursal, CreateProductRequest request)
    {
        await ValidateReferencesAsync(idEmpresa, request, null);
        await ValidateBranchAsync(idEmpresa, idSucursal);
        await ValidateCompositionAsync(idEmpresa, 0, request);
        await using var transaction = _context.Database.CurrentTransaction == null
            ? await _context.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted) : null;
        var codigo = await NextCodeAsync(idEmpresa, transaction ?? _context.Database.CurrentTransaction!);
        var now = DateTime.UtcNow;
        var product = new Producto
        {
            IdEmpresa = idEmpresa, Codigo = codigo, Activo = true,
            FechaCreacion = now, FechaModificacion = now
        };
        Apply(product, request);
        _context.Productos.Add(product);
        await _context.SaveChangesAsync();
        await _priceLists.SetDefaultListPriceAsync(idEmpresa, product.Id, product.PrecioConIva);
        if (request.Stock != null) await SaveStockValueAsync(product.Id, idSucursal, request.Stock);
        await SaveCompositionAsync(idEmpresa, product.Id, request);
        if (transaction != null) await transaction.CommitAsync();
        return (await GetAsync(idEmpresa, product.Id, idSucursal))!;
    }

    public async Task<ProductDetailDto> UpdateAsync(int idEmpresa, int idSucursal, int id, UpdateProductRequest request)
    {
        await using var transaction = _context.Database.CurrentTransaction == null
            ? await _context.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted) : null;
        var product = await _context.Productos.FirstOrDefaultAsync(p => p.Id == id && p.IdEmpresa == idEmpresa)
            ?? throw new ProductoException("Producto no encontrado.", 404);
        await ValidateReferencesAsync(idEmpresa, request, id);
        await ValidateCompositionAsync(idEmpresa, id, request);
        Apply(product, request);
        product.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync();
        await _priceLists.SetDefaultListPriceAsync(idEmpresa, product.Id, product.PrecioConIva);
        if (request.Stock != null)
        {
            await ValidateBranchAsync(idEmpresa, idSucursal);
            await SaveStockValueAsync(id, idSucursal, request.Stock);
        }
        await SaveCompositionAsync(idEmpresa, id, request);
        if (transaction != null) await transaction.CommitAsync();
        return (await GetAsync(idEmpresa, id, idSucursal))!;
    }

    public async Task<List<ReferenciaDto>> ComponentOptionsAsync(int company, string? text)
    {
        var query = _context.Productos.AsNoTracking().Where(p => p.IdEmpresa == company && p.Activo
            && p.TipoProducto.Replace(" ", "").ToLower() == "productosimple");
        if (!string.IsNullOrWhiteSpace(text))
        {
            var term = text.Trim();
            query = int.TryParse(term, out var code)
                ? query.Where(p => p.Codigo == code || EF.Functions.ILike(p.Nombre, $"%{term}%"))
                : query.Where(p => EF.Functions.ILike(p.Nombre, $"%{term}%"));
        }
        return await query.OrderBy(p => p.Nombre).ThenBy(p => p.Id).Take(50)
            .Select(p => new ReferenciaDto(p.Id, p.Nombre)).ToListAsync();
    }

    private async Task ValidateCompositionAsync(int company, int id, CreateProductRequest request)
    {
        var compound = NormalizeProductType(request.TipoProducto) == "Producto compuesto";
        if (!compound)
        {
            if (request.Componentes?.Count > 0) throw new ProductoException("Un producto simple no puede tener componentes.");
            return;
        }
        if (id != 0 && await _context.ProductComponents.AnyAsync(c => c.ComponentProductId == id))
            throw new ProductoException("Este producto se usa como componente. Quitalo de esas composiciones antes de convertirlo en compuesto.");
        var values = request.Componentes;
        if (values == null && id != 0)
            values = await _context.ProductComponents.Where(c => c.CompositeProductId == id)
                .Select(c => new ProductComponentRequest { ProductId = c.ComponentProductId, Quantity = c.Quantity }).ToListAsync();
        try { await new StockMovementService(_context).ValidateComponentsAsync(company, id, values ?? []); }
        catch (SaleException e) { throw new ProductoException(e.Message, e.StatusCode); }
    }

    private async Task SaveCompositionAsync(int company, int id, CreateProductRequest request)
    {
        if (NormalizeProductType(request.TipoProducto) == "Producto compuesto")
        {
            if (request.Componentes != null)
            {
                try { await new StockMovementService(_context).SaveComponentsAsync(company, id, request.Componentes); }
                catch (SaleException e) { throw new ProductoException(e.Message, e.StatusCode); }
            }
        }
        else
        {
            _context.ProductComponents.RemoveRange(_context.ProductComponents.Where(c => c.CompositeProductId == id));
            await _context.SaveChangesAsync();
        }
    }

    public async Task SetStatusAsync(int idEmpresa, int id, bool activo)
    {
        var product = await _context.Productos.FirstOrDefaultAsync(p => p.Id == id && p.IdEmpresa == idEmpresa)
            ?? throw new ProductoException("Producto no encontrado.", 404);
        product.Activo = activo;
        product.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync();
    }

    public async Task DeleteAsync(int idEmpresa, int id)
    {
        var product = await _context.Productos.FirstOrDefaultAsync(p => p.Id == id && p.IdEmpresa == idEmpresa)
            ?? throw new ProductoException("Producto no encontrado.", 404);
        product.Activo = false;
        product.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync();
    }

    public async Task<Producto> GetEntityAsync(int idEmpresa, int id) =>
        await _context.Productos.FirstOrDefaultAsync(p => p.Id == id && p.IdEmpresa == idEmpresa)
        ?? throw new ProductoException("Producto no encontrado.", 404);

    /// Resolución exacta para pistoleo en el punto de venta.
    public async Task<ProductDetailDto?> GetByBarcodeAsync(int idEmpresa, string barcode)
    {
        var code = barcode.Trim();
        if (code.Length == 0) return null;
        var product = await _context.Productos.AsNoTracking()
            .Include(p => p.Rubro).Include(p => p.SubRubro).Include(p => p.Alicuota)
            .FirstOrDefaultAsync(p => p.IdEmpresa == idEmpresa && p.Activo && p.CodigoBarras == code);
        return product == null ? null : ToDetail(product);
    }

    public Task SaveAsync() => _context.SaveChangesAsync();

    public async Task<ProductStockDto?> GetStockAsync(int idEmpresa, int idProducto, int idSucursal)
    {
        await ValidateProductAndBranchAsync(idEmpresa, idProducto, idSucursal);
        return await GetStockValueAsync(idProducto, idSucursal);
    }

    private async Task<ProductStockDto?> GetStockValueAsync(int idProducto, int idSucursal) =>
        await _context.StockProductos.AsNoTracking()
            .Where(s => s.IdProducto == idProducto && s.IdSucursal == idSucursal)
            .Select(s => new ProductStockDto
            {
                Id = s.Id, IdProducto = s.IdProducto, IdSucursal = s.IdSucursal,
                OperacionCantidad = s.OperacionCantidad, StockActual = s.StockActual,
                StockMinimo = s.StockMinimo, StockIdeal = s.StockIdeal,
                TieneAlarmaStock = s.TieneAlarmaStock,
                TieneAlarmaStockMinimo = s.TieneAlarmaStockMinimo,
                ComprobarStockAlVender = s.ComprobarStockAlVender,
                ActualizarSobre = s.ActualizarSobre, FechaModificacion = s.FechaModificacion
            }).FirstOrDefaultAsync();

    public async Task<ProductStockDto> UpsertStockAsync(int idEmpresa, int idProducto, int idSucursal, ProductStockRequest request)
    {
        await ValidateProductAndBranchAsync(idEmpresa, idProducto, idSucursal);
        await SaveStockValueAsync(idProducto, idSucursal, request);
        return (await GetStockValueAsync(idProducto, idSucursal))!;
    }

    private async Task SaveStockValueAsync(int idProducto, int idSucursal, ProductStockRequest request)
    {
        var operation = request.OperacionCantidad.Trim();
        if (operation is not ("Entero" or "Decimal")) throw new ProductoException("OperacionCantidad debe ser Entero o Decimal.");
        var updateOn = request.ActualizarSobre.Trim();
        if (updateOn is not ("Producto" or "Ingrediente")) throw new ProductoException("ActualizarSobre debe ser Producto o Ingrediente.");
        if (request.StockActual < 0 || request.StockMinimo < 0 || request.StockIdeal < 0)
            throw new ProductoException("Las cantidades de stock no pueden ser negativas.");
        if (request.StockIdeal < request.StockMinimo)
            throw new ProductoException("El stock ideal no puede ser menor que el stock mínimo.");
        if (operation == "Entero" && new[] { request.StockActual, request.StockMinimo, request.StockIdeal }.Any(v => v != decimal.Truncate(v)))
            throw new ProductoException("Las cantidades no pueden tener decimales cuando la operación es Entero.");

        var entity = await _context.StockProductos.FirstOrDefaultAsync(s => s.IdProducto == idProducto && s.IdSucursal == idSucursal);
        if (entity == null)
        {
            entity = new StockProducto { IdProducto = idProducto, IdSucursal = idSucursal };
            _context.StockProductos.Add(entity);
        }
        entity.OperacionCantidad = operation; entity.StockActual = decimal.Round(request.StockActual, 3);
        entity.StockMinimo = decimal.Round(request.StockMinimo, 3); entity.StockIdeal = decimal.Round(request.StockIdeal, 3);
        entity.TieneAlarmaStock = request.TieneAlarmaStock; entity.TieneAlarmaStockMinimo = request.TieneAlarmaStockMinimo;
        entity.ComprobarStockAlVender = request.ComprobarStockAlVender; entity.ActualizarSobre = updateOn;
        entity.FechaModificacion = DateTime.UtcNow;
        await _context.SaveChangesAsync();
    }

    private async Task ValidateProductAndBranchAsync(int idEmpresa, int idProducto, int idSucursal)
    {
        if (!await _context.Productos.AnyAsync(p => p.Id == idProducto && p.IdEmpresa == idEmpresa))
            throw new ProductoException("Producto no encontrado.", 404);
        await ValidateBranchAsync(idEmpresa, idSucursal);
    }

    private async Task ValidateBranchAsync(int idEmpresa, int idSucursal)
    {
        if (!await _context.Sucursales.AnyAsync(s => s.Id == idSucursal && s.IdEmpresa == idEmpresa))
            throw new ProductoException("La sucursal no existe o no pertenece a la empresa.", 404);
    }

    private async Task ValidateReferencesAsync(int idEmpresa, CreateProductRequest request, int? exceptId)
    {
        if (string.IsNullOrWhiteSpace(request.Nombre)) throw new ProductoException("El nombre es obligatorio.");
        if (request.CostoConIva < 0 || request.PrecioConIva < 0)
            throw new ProductoException("El costo y el precio no pueden ser negativos.");

        var rubroExists = await _context.Rubros.AnyAsync(r => r.Id == request.IdRubro && r.IdEmpresa == idEmpresa && r.Activo);
        if (!rubroExists) throw new ProductoException("El rubro no existe o no pertenece a la empresa.");

        if (request.IdSubRubro.HasValue &&
            !await _context.SubRubros.AnyAsync(s => s.Id == request.IdSubRubro && s.IdRubro == request.IdRubro && s.IdEmpresa == idEmpresa && s.Activo))
            throw new ProductoException("El subrubro no pertenece al rubro seleccionado.");

        if (!await _context.Alicuotas.AnyAsync(a => a.Id == request.IdAlicuota && a.Activa && (a.IdEmpresa == null || a.IdEmpresa == idEmpresa)))
            throw new ProductoException("La alícuota no existe o no está disponible para la empresa.");

        if (!string.IsNullOrWhiteSpace(request.CodigoBarras))
        {
            var barcode = request.CodigoBarras.Trim();
            if (await _context.Productos.AnyAsync(p => p.IdEmpresa == idEmpresa && p.Id != exceptId && p.CodigoBarras == barcode))
                throw new ProductoException("Ya existe un producto con ese código de barras.", 409);
        }
    }

    private static void Apply(Producto p, CreateProductRequest r)
    {
        p.Nombre = r.Nombre.Trim(); p.CodigoBarras = string.IsNullOrWhiteSpace(r.CodigoBarras) ? null : r.CodigoBarras.Trim();
        p.Descripcion = r.Descripcion?.Trim(); p.TipoProducto = NormalizeProductType(r.TipoProducto);
        p.IdRubro = r.IdRubro; p.IdSubRubro = r.IdSubRubro; p.IdAlicuota = r.IdAlicuota;
        p.CostoConIva = decimal.Round(r.CostoConIva, 2); p.PrecioConIva = decimal.Round(r.PrecioConIva, 2);
        p.MostrarDelivery = r.MostrarDelivery; p.MostrarSalon = r.MostrarSalon;
        p.MostrarCartaDigital = r.MostrarCartaDigital; p.SolicitarCantidad = r.SolicitarCantidad;
        p.SolicitarPrecioUnitario = r.SolicitarPrecioUnitario;
        p.SolicitarPrecioYCalcularCantidad = r.SolicitarPrecioYCalcularCantidad;
        p.Preparacion = r.Preparacion?.Trim(); p.Orden = r.Orden;
    }

    private static string NormalizeProductType(string value)
    {
        var compact = value.Replace(" ", string.Empty).Trim();
        if (compact.Equals("ProductoSimple", StringComparison.OrdinalIgnoreCase)) return "ProductoSimple";
        if (compact.Equals("ProductoCompuesto", StringComparison.OrdinalIgnoreCase)) return "Producto compuesto";
        return value.Trim();
    }

    private async Task<int> NextCodeAsync(int idEmpresa, IDbContextTransaction transaction)
    {
        await using var command = _context.Database.GetDbConnection().CreateCommand();
        command.Transaction = transaction.GetDbTransaction();
        command.CommandText = """
            INSERT INTO producto_codigo_contadores (id_empresa, ultimo_codigo)
            VALUES (@idEmpresa, 1)
            ON CONFLICT (id_empresa)
            DO UPDATE SET ultimo_codigo = producto_codigo_contadores.ultimo_codigo + 1
            RETURNING ultimo_codigo;
            """;
        var parameter = command.CreateParameter();
        parameter.ParameterName = "idEmpresa"; parameter.Value = idEmpresa;
        command.Parameters.Add(parameter);
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    private static ProductDetailDto ToDetail(Producto p)
    {
        var divisor = 1 + p.Alicuota.Porcentaje / 100m;
        var costoSinIva = decimal.Round(p.CostoConIva / divisor, 2, MidpointRounding.AwayFromZero);
        var precioSinIva = decimal.Round(p.PrecioConIva / divisor, 2, MidpointRounding.AwayFromZero);
        return new ProductDetailDto
        {
            Id = p.Id, Codigo = p.Codigo, CodigoBarras = p.CodigoBarras, Nombre = p.Nombre, Descripcion = p.Descripcion,
            TipoProducto = p.TipoProducto, Rubro = new ReferenciaDto(p.Rubro.Id, p.Rubro.Nombre),
            SubRubro = p.SubRubro == null ? null : new ReferenciaDto(p.SubRubro.Id, p.SubRubro.Nombre),
            Alicuota = new AlicuotaReferenciaDto(p.Alicuota.Id, p.Alicuota.Nombre, p.Alicuota.Descripcion, p.Alicuota.Porcentaje),
            CostoConIva = p.CostoConIva, PrecioConIva = p.PrecioConIva,
            CostoSinIva = costoSinIva, PrecioSinIva = precioSinIva,
            RentabilidadPorcentaje = costoSinIva == 0 ? 0 : decimal.Round(((precioSinIva - costoSinIva) / costoSinIva) * 100, 2, MidpointRounding.AwayFromZero),
            ImagenUrl = p.ImagenUrl, Activo = p.Activo, MostrarDelivery = p.MostrarDelivery,
            MostrarSalon = p.MostrarSalon, MostrarCartaDigital = p.MostrarCartaDigital,
            SolicitarCantidad = p.SolicitarCantidad, SolicitarPrecioUnitario = p.SolicitarPrecioUnitario,
            SolicitarPrecioYCalcularCantidad = p.SolicitarPrecioYCalcularCantidad,
            Preparacion = p.Preparacion, Orden = p.Orden,
            FechaCreacion = p.FechaCreacion, FechaModificacion = p.FechaModificacion
        };
    }
}
