using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Controllers
{
    public class UploadEmpresaImagenRequest
    {
        public IFormFile Imagen { get; set; } = null!;
    }

    [Route("api/empresas")]
    [ApiController]
    public class EmpresasController : ControllerBase
    {
        private const long MaxImageSize = 5 * 1024 * 1024;
        private readonly AppDbContext _context;
        private readonly IWebHostEnvironment _environment;

        public EmpresasController(AppDbContext context, IWebHostEnvironment environment)
        {
            _context = context;
            _environment = environment;
        }

        [HttpPost("{id:int}/imagen")]
        [Consumes("multipart/form-data")]
        public async Task<ActionResult<ApiResponse<Empresa>>> UploadImage(
            int id,
            [FromForm] UploadEmpresaImagenRequest request)
        {
            var imagen = request.Imagen;

            if (imagen == null || imagen.Length == 0)
                return BadRequest(ApiResponse<Empresa>.Fail("Debe enviar una imagen.", 400));

            if (imagen.Length > MaxImageSize)
                return BadRequest(ApiResponse<Empresa>.Fail("La imagen no puede superar los 5 MB.", 400));

            var extension = await GetImageExtensionAsync(imagen);
            if (extension == null)
                return BadRequest(ApiResponse<Empresa>.Fail("Formato no permitido. Use JPG, PNG o WebP.", 400));

            var empresa = await _context.Empresas.FirstOrDefaultAsync(e => e.Id == id);
            if (empresa == null)
                return NotFound(ApiResponse<Empresa>.Fail("Empresa no encontrada.", 404));

            var fileName = $"{id}-{Guid.NewGuid():N}{extension}";
            var webRoot = _environment.WebRootPath
                ?? Path.Combine(_environment.ContentRootPath, "wwwroot");
            var uploadDirectory = Path.Combine(webRoot, "uploads", "empresas");
            Directory.CreateDirectory(uploadDirectory);

            await using (var stream = System.IO.File.Create(Path.Combine(uploadDirectory, fileName)))
            {
                await imagen.CopyToAsync(stream);
            }

            empresa.ImagenUrl = $"/uploads/empresas/{fileName}";
            await _context.SaveChangesAsync();

            return Ok(ApiResponse<Empresa>.Ok(empresa));
        }

        private static async Task<string?> GetImageExtensionAsync(IFormFile image)
        {
            var header = new byte[12];
            await using var stream = image.OpenReadStream();
            var bytesRead = await stream.ReadAsync(header);

            if (bytesRead >= 3 &&
                header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF)
                return ".jpg";

            if (bytesRead >= 8 &&
                header[0] == 0x89 && header[1] == 0x50 &&
                header[2] == 0x4E && header[3] == 0x47 &&
                header[4] == 0x0D && header[5] == 0x0A &&
                header[6] == 0x1A && header[7] == 0x0A)
                return ".png";

            if (bytesRead >= 12 &&
                header[0] == 0x52 && header[1] == 0x49 &&
                header[2] == 0x46 && header[3] == 0x46 &&
                header[8] == 0x57 && header[9] == 0x45 &&
                header[10] == 0x42 && header[11] == 0x50)
                return ".webp";

            return null;
        }
    }
}
