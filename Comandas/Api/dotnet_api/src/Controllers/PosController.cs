using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize]
[Route("api/pos")]
public class PosController(PosService service) : ControllerBase
{
    /// Mesa virtual de venta directa (mostrador) de la sucursal actual; se crea si no existe.
    [HttpGet("mostrador")]
    public async Task<ActionResult<ApiResponse<object>>> GetCounterTable()
    {
        try
        {
            var (tableId, tableName) = await service.EnsureCounterTableAsync(Company, Branch);
            return Ok(ApiResponse<object>.Ok(new { tableId, tableName }));
        }
        catch (PosException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); }
    }

    private int Company => Claim("id_empresa", "empresa");
    private int Branch => Claim("id_sucursal", "sucursal");
    private int Claim(string name, string label) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new PosException($"El token no contiene una {label} válida.", 401);
}

public sealed class PosException(string message, int statusCode = 400) : Exception(message) { public int StatusCode { get; } = statusCode; }
