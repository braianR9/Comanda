using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/subrubros")]
public class SubRubrosController(CatalogosService service, IWebHostEnvironment environment) : CatalogControllerBase
{
    private const long MaxImageSize = 5 * 1024 * 1024;
    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<SubRubroDto>>> Get(int id)
    { try { var value = await service.GetSubRubroAsync(CompanyId, id); return value == null ? NotFound(ApiResponse<SubRubroDto>.NotFound("Subrubro no encontrado.")) : Ok(ApiResponse<SubRubroDto>.Ok(value)); } catch (CatalogoException e) { return CatalogError<SubRubroDto>(e); } }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<SubRubroDto>>> Update(int id, UpdateSubRubroRequest request)
    { try { return Ok(ApiResponse<SubRubroDto>.Ok(await service.UpdateSubRubroAsync(CompanyId, id, request))); } catch (CatalogoException e) { return CatalogError<SubRubroDto>(e); } }

    [HttpPatch("{id:int}/estado")]
    public async Task<ActionResult<ApiResponse<object>>> Status(int id, CatalogStatusRequest request)
    { try { await service.SetSubRubroStatusAsync(CompanyId, id, request.Activo); return Ok(ApiResponse<object>.Ok(new { id, request.Activo })); } catch (CatalogoException e) { return CatalogError<object>(e); } }

    [HttpDelete("{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(int id)
    { try { await service.DeleteSubRubroAsync(CompanyId, id); return Ok(ApiResponse<object>.Ok(new { id })); } catch (CatalogoException e) { return CatalogError<object>(e); } }

    [HttpPost("{id:int}/imagen")]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<ApiResponse<SubRubroDto>>> UploadImage(int id, [FromForm] UploadSubRubroImageRequest request)
    {
        if (request.Imagen is null || request.Imagen.Length == 0) return BadRequest(ApiResponse<SubRubroDto>.Fail("Debe enviar una imagen."));
        if (request.Imagen.Length > MaxImageSize) return BadRequest(ApiResponse<SubRubroDto>.Fail("La imagen no puede superar los 5 MB."));
        var extension = await DetectImageExtensionAsync(request.Imagen);
        if (extension == null) return BadRequest(ApiResponse<SubRubroDto>.Fail("Formato no permitido. Use JPG, PNG o WEBP."));
        try
        {
            var subrubro = await service.GetSubRubroEntityAsync(CompanyId, id);
            var oldPath = LocalImagePath(subrubro.ImagenUrl); var directory = UploadDirectory(); Directory.CreateDirectory(directory);
            var fileName = $"{CompanyId}-{id}-{Guid.NewGuid():N}{extension}";
            await using (var stream = System.IO.File.Create(Path.Combine(directory, fileName))) await request.Imagen.CopyToAsync(stream);
            subrubro.ImagenUrl = $"/uploads/subrubros/{fileName}";
            await service.SaveAsync(); DeleteIfExists(oldPath);
            return Ok(ApiResponse<SubRubroDto>.Ok((await service.GetSubRubroAsync(CompanyId, id))!));
        }
        catch (CatalogoException e) { return CatalogError<SubRubroDto>(e); }
    }

    [HttpDelete("{id:int}/imagen")]
    public async Task<ActionResult<ApiResponse<object>>> DeleteImage(int id)
    {
        try
        {
            var subrubro = await service.GetSubRubroEntityAsync(CompanyId, id);
            var oldPath = LocalImagePath(subrubro.ImagenUrl); subrubro.ImagenUrl = null;
            await service.SaveAsync(); DeleteIfExists(oldPath);
            return Ok(ApiResponse<object>.Ok(new { id, imagenUrl = (string?)null }));
        }
        catch (CatalogoException e) { return CatalogError<object>(e); }
    }

    private string UploadDirectory() => Path.Combine(environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot"), "uploads", "subrubros");
    private string? LocalImagePath(string? relative) => string.IsNullOrWhiteSpace(relative) ? null : Path.Combine(
        environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot"), relative.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
    private static void DeleteIfExists(string? path) { if (path != null && System.IO.File.Exists(path)) System.IO.File.Delete(path); }
    private static async Task<string?> DetectImageExtensionAsync(IFormFile image)
    {
        var header = new byte[12]; await using var stream = image.OpenReadStream(); var read = await stream.ReadAsync(header);
        if (read >= 3 && header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff) return ".jpg";
        if (read >= 8 && header[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a })) return ".png";
        if (read >= 12 && header[..4].SequenceEqual("RIFF"u8.ToArray()) && header[8..12].SequenceEqual("WEBP"u8.ToArray())) return ".webp";
        return null;
    }
}
