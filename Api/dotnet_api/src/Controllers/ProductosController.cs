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

    [HttpGet]
    public async Task<ActionResult<ApiResponse<PagedResult<ProductListDto>>>> GetAll(
        [FromQuery] string? texto, [FromQuery] int? idRubro, [FromQuery] int? idSubRubro,
        [FromQuery] bool? activo, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var company = GetCompanyId();
        if (company == null) return Unauthorized(ApiResponse<PagedResult<ProductListDto>>.Fail("El token no contiene una empresa válida.", 401));
        return Ok(ApiResponse<PagedResult<ProductListDto>>.Ok(
            await _service.GetAllAsync(company.Value, texto, idRubro, idSubRubro, activo, page, pageSize)));
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
