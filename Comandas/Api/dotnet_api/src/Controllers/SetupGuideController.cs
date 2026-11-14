using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

/// Guía de puesta en marcha: qué falta configurar para que el local empiece a operar.
[ApiController, Authorize]
[Route("api/puesta-en-marcha")]
public class SetupGuideController(SetupGuideService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get()
    {
        if (User.FindFirstValue("rol_nombre") is not ("ADMIN" or "CAJA" or "ENCARGADO"))
            return StatusCode(403, ApiResponse<object>.Fail("Requiere ADMIN o CAJA.", 403));
        var company = int.Parse(User.FindFirstValue("id_empresa")!);
        var branch = int.Parse(User.FindFirstValue("id_sucursal")!);
        return Ok(ApiResponse<object>.Ok(await service.StatusAsync(company, branch)));
    }
}
