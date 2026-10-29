using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/productos")]
public class ProductosController : ControllerBase
{
    private const long MaxImageSize = 5 * 1024 * 1024;
    private readonly ProductoService _service;
    private readonly IWebHostEnvironment _environment;

    public ProductosController(ProductoService service, IWebHostEnvironment environment)
    {
        _service = service;
        _environment = environment;
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPost("importar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<ActionResult<ApiResponse<ProductImportResult>>> Import(
        IFormFile archivo, [FromForm] bool confirmar = false, [FromQuery] bool progreso = false)
    {
        var company = GetCompanyId();
        var branch = GetBranchId();
        if (company == null || branch == null)
            return Unauthorized(ApiResponse<ProductImportResult>.Fail("El token no contiene empresa y sucursal válidas.", 401));
        if (archivo == null || archivo.Length == 0 || archivo.Length > 5 * 1024 * 1024 ||
            !Path.GetExtension(archivo.FileName).Equals(".xlsx", StringComparison.OrdinalIgnoreCase))
            return BadRequest(ApiResponse<ProductImportResult>.Fail("Seleccione un archivo .xlsx de hasta 5 MB."));
        ProductImportResult result;
        // Parse separately so invalid workbook errors never mask database failures.
        using var buffer = new MemoryStream();
        await archivo.CopyToAsync(buffer);
        if (progreso)
        {
            Response.ContentType = "application/x-ndjson; charset=utf-8";
            Response.Headers.CacheControl = "no-cache, no-transform";
            Response.Headers["X-Accel-Buffering"] = "no";
            HttpContext.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpResponseBodyFeature>()?.DisableBuffering();
            async Task Send(object message)
            {
                HttpContext.RequestAborted.ThrowIfCancellationRequested();
                await Response.WriteAsync(System.Text.Json.JsonSerializer.Serialize(message,
                    new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web)) + "\n",
                    HttpContext.RequestAborted);
                await Response.Body.FlushAsync(HttpContext.RequestAborted);
            }
            try
            {
                buffer.Position = 0;
                result = await _service.ImportWorkbookAsync(company.Value, branch.Value, buffer, confirmar,
                    p => Send(new { tipo = "progreso", p.Etapa, p.Procesados, p.Total }));
                await Send(new { tipo = "resultado", data = result });
            }
            catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested) { }
            catch (Exception ex)
            {
                HttpContext.RequestServices.GetRequiredService<ILogger<ProductosController>>()
                    .LogError(ex, "Error al importar productos para empresa {Company}", company);
                if (!HttpContext.RequestAborted.IsCancellationRequested)
                    await Send(new { tipo = "error", error = ex is ProductoException ? ex.Message
                        : "No se pudo completar la importación. Revisá el archivo y la conexión con la base de datos." });
            }
            return new EmptyResult();
        }
        try { buffer.Position = 0; ProductoService.ReadProductWorkbook(buffer); }
        catch (ProductoException ex) { return Error<ProductImportResult>(ex); }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        { return BadRequest(ApiResponse<ProductImportResult>.Fail("El archivo no es un Excel válido o está dañado.")); }
        buffer.Position = 0;
        try { result = await _service.ImportWorkbookAsync(company.Value, branch.Value, buffer, confirmar); }
        catch (ProductoException ex) { return Error<ProductImportResult>(ex); }
        return Ok(ApiResponse<ProductImportResult>.Ok(result));
    }

    [HttpGet]
    public async Task<ActionResult<ApiResponse<PagedResult<ProductListDto>>>> GetAll(
        [FromQuery] string? texto, [FromQuery] int? idRubro, [FromQuery] int? idSubRubro,
        [FromQuery] bool? activo, [FromQuery] string? orden, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<PagedResult<ProductListDto>>.Fail("El token no contiene una empresa válida.", 401));
        return Ok(ApiResponse<PagedResult<ProductListDto>>.Ok(
            await _service.GetAllAsync(company.Value, texto, idRubro, idSubRubro, activo, page, pageSize, orden)));
    }

    [HttpGet("componentes-disponibles")]
    public async Task<ActionResult<ApiResponse<List<ReferenciaDto>>>> ComponentOptions([FromQuery] string? texto)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<List<ReferenciaDto>>.Fail("El token no contiene una empresa válida.", 401));
        return Ok(ApiResponse<List<ReferenciaDto>>.Ok(await _service.ComponentOptionsAsync(company.Value, texto)));
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<ProductDetailDto>>> Get(int id)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una empresa válida.", 401));
        var branch = GetBranchId();
        if (branch == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una sucursal válida.", 401));
        var product = await _service.GetAsync(company.Value, id, branch.Value);
        return product == null
            ? NotFound(ApiResponse<ProductDetailDto>.NotFound("Producto no encontrado."))
            : Ok(ApiResponse<ProductDetailDto>.Ok(product));
    }

    /// Resolución exacta por código de barras, usada por el pistoleo del punto de venta.
    [HttpGet("codigo-barras/{codigo}")]
    public async Task<ActionResult<ApiResponse<ProductDetailDto>>> GetByBarcode(string codigo)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una empresa válida.", 401));
        var product = await _service.GetByBarcodeAsync(company.Value, codigo);
        return product == null
            ? NotFound(ApiResponse<ProductDetailDto>.NotFound("No se encontró un producto con ese código de barras."))
            : Ok(ApiResponse<ProductDetailDto>.Ok(product));
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPost]
    public async Task<ActionResult<ApiResponse<ProductDetailDto>>> Create(CreateProductRequest request)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una empresa válida.", 401));
        var branch = GetBranchId();
        if (branch == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una sucursal válida.", 401));
        try
        {
            var product = await _service.CreateAsync(company.Value, branch.Value, request);
            return StatusCode(201, ApiResponse<ProductDetailDto>.Ok(product, 201));
        }
        catch (ProductoException ex) { return Error<ProductDetailDto>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<ProductDetailDto>>> Update(int id, UpdateProductRequest request)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una empresa válida.", 401));
        var branch = GetBranchId();
        if (branch == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una sucursal válida.", 401));
        try { return Ok(ApiResponse<ProductDetailDto>.Ok(await _service.UpdateAsync(company.Value, branch.Value, id, request))); }
        catch (ProductoException ex) { return Error<ProductDetailDto>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPatch("{id:int}/estado")]
    public async Task<ActionResult<ApiResponse<object>>> SetStatus(int id, UpdateProductStatusRequest request)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<object>.Fail("El token no contiene una empresa válida.", 401));
        try
        {
            await _service.SetStatusAsync(company.Value, id, request.Activo);
            return Ok(ApiResponse<object>.Ok(new { id, request.Activo }));
        }
        catch (ProductoException ex) { return Error<object>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpDelete("{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(int id)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<object>.Fail("El token no contiene una empresa válida.", 401));
        try
        {
            await _service.DeleteAsync(company.Value, id);
            return Ok(ApiResponse<object>.Ok(new { id, activo = false }));
        }
        catch (ProductoException ex) { return Error<object>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPost("{id:int}/imagen")]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<ApiResponse<ProductDetailDto>>> UploadImage(int id, [FromForm] UploadProductImageRequest request)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductDetailDto>.Fail("El token no contiene una empresa válida.", 401));
        if (request.Imagen is null || request.Imagen.Length == 0)
            return BadRequest(ApiResponse<ProductDetailDto>.Fail("Debe enviar una imagen."));
        if (request.Imagen.Length > MaxImageSize)
            return BadRequest(ApiResponse<ProductDetailDto>.Fail("La imagen no puede superar los 5 MB."));
        var extension = await DetectImageExtensionAsync(request.Imagen);
        if (extension == null)
            return BadRequest(ApiResponse<ProductDetailDto>.Fail("Formato no permitido. Use JPG, PNG o WEBP."));

        try
        {
            var product = await _service.GetEntityAsync(company.Value, id);
            var directory = UploadDirectory();
            Directory.CreateDirectory(directory);
            var oldPath = LocalImagePath(product.ImagenUrl);
            var fileName = $"{company}-{id}-{Guid.NewGuid():N}{extension}";
            await using (var stream = System.IO.File.Create(Path.Combine(directory, fileName)))
                await request.Imagen.CopyToAsync(stream);
            product.ImagenUrl = $"/uploads/productos/{fileName}";
            product.FechaModificacion = DateTime.UtcNow;
            await _service.SaveAsync();
            DeleteIfExists(oldPath);
            return Ok(ApiResponse<ProductDetailDto>.Ok((await _service.GetAsync(company.Value, id, GetBranchId()))!));
        }
        catch (ProductoException ex) { return Error<ProductDetailDto>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpDelete("{id:int}/imagen")]
    public async Task<ActionResult<ApiResponse<object>>> DeleteImage(int id)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<object>.Fail("El token no contiene una empresa válida.", 401));
        try
        {
            var product = await _service.GetEntityAsync(company.Value, id);
            var oldPath = LocalImagePath(product.ImagenUrl);
            product.ImagenUrl = null;
            product.FechaModificacion = DateTime.UtcNow;
            await _service.SaveAsync();
            DeleteIfExists(oldPath);
            return Ok(ApiResponse<object>.Ok(new { id, imagenUrl = (string?)null }));
        }
        catch (ProductoException ex) { return Error<object>(ex); }
    }

    [HttpGet("{id:int}/stock/{idSucursal:int}")]
    public async Task<ActionResult<ApiResponse<ProductStockDto>>> GetStock(int id, int idSucursal)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductStockDto>.Fail("El token no contiene una empresa válida.", 401));
        try
        {
            var stock = await _service.GetStockAsync(company.Value, id, idSucursal);
            return stock == null
                ? NotFound(ApiResponse<ProductStockDto>.NotFound("El producto todavía no tiene stock configurado para la sucursal."))
                : Ok(ApiResponse<ProductStockDto>.Ok(stock));
        }
        catch (ProductoException ex) { return Error<ProductStockDto>(ex); }
    }

    [Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
    [HttpPut("{id:int}/stock/{idSucursal:int}")]
    public async Task<ActionResult<ApiResponse<ProductStockDto>>> UpsertStock(int id, int idSucursal, ProductStockRequest request)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<ProductStockDto>.Fail("El token no contiene una empresa válida.", 401));
        try { return Ok(ApiResponse<ProductStockDto>.Ok(await _service.UpsertStockAsync(company.Value, id, idSucursal, request))); }
        catch (ProductoException ex) { return Error<ProductStockDto>(ex); }
    }

    private int? GetCompanyId() => int.TryParse(User.FindFirstValue("id_empresa"), out var id) ? id : null;
    private int? GetBranchId() => int.TryParse(User.FindFirstValue("id_sucursal"), out var id) ? id : null;
    private string UploadDirectory() => Path.Combine(_environment.WebRootPath ?? Path.Combine(_environment.ContentRootPath, "wwwroot"), "uploads", "productos");
    private string? LocalImagePath(string? relative) => string.IsNullOrWhiteSpace(relative) ? null : Path.Combine(
        _environment.WebRootPath ?? Path.Combine(_environment.ContentRootPath, "wwwroot"), relative.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
    private static void DeleteIfExists(string? path) { if (path != null && System.IO.File.Exists(path)) System.IO.File.Delete(path); }

    private ActionResult<ApiResponse<T>> Error<T>(ProductoException ex) =>
        StatusCode(ex.StatusCode, ApiResponse<T>.Fail(ex.Message, ex.StatusCode));

    private static async Task<string?> DetectImageExtensionAsync(IFormFile image)
    {
        var header = new byte[12];
        await using var stream = image.OpenReadStream();
        var read = await stream.ReadAsync(header);
        if (read >= 3 && header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff) return ".jpg";
        if (read >= 8 && header[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a })) return ".png";
        if (read >= 12 && header[..4].SequenceEqual("RIFF"u8.ToArray()) && header[8..12].SequenceEqual("WEBP"u8.ToArray())) return ".webp";
        return null;
    }
}
