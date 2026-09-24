using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/cajas")]
public class CajasController(CajaService service) : ControllerBase
{
    private static readonly string[] RolesAutorizados = ["ADMIN", "ENCARGADO"];

    [HttpGet("actual")]
    public async Task<ActionResult<ApiResponse<CajaDto?>>> Actual() =>
        Ok(ApiResponse<CajaDto?>.Ok(await service.GetActualAsync(Company, Branch)));

    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<CajaDto>>>> Historial([FromQuery] int take = 20) =>
        await Run(() => service.HistorialAsync(Company, Branch, take));

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<CajaDto>>> Get(int id)
    {
        var caja = await service.GetAsync(Company, Branch, id);
        return caja == null ? NotFound(ApiResponse<CajaDto>.NotFound("Caja no encontrada.")) : Ok(ApiResponse<CajaDto>.Ok(caja));
    }

    [HttpPost("abrir")]
    public async Task<ActionResult<ApiResponse<CajaDto>>> Abrir(AbrirCajaRequest request)
    {
        if (!EsAutorizado()) return Forbid();
        return await Run(() => service.AbrirAsync(Company, Branch, UserId, request), 201);
    }

    [HttpPost("{id:int}/cerrar")]
    public async Task<ActionResult<ApiResponse<CajaDto>>> Cerrar(int id, CerrarCajaRequest request)
    {
        if (!EsAutorizado()) return Forbid();
        return await Run(() => service.CerrarAsync(Company, Branch, UserId, id, request));
    }

    [HttpPost("{id:int}/movimientos")]
    public async Task<ActionResult<ApiResponse<CajaMovimientoDto>>> Movimiento(int id, CajaMovimientoRequest request)
    {
        if (!EsAutorizado()) return Forbid();
        return await Run(() => service.AgregarMovimientoAsync(Company, Branch, UserId, id, request), 201);
    }

    private bool EsAutorizado() => RolesAutorizados.Contains(User.FindFirstValue("rol_nombre"));
    private int Company => Claim("id_empresa");
    private int Branch => Claim("id_sucursal");
    private int UserId => Claim(ClaimTypes.NameIdentifier);
    private int Claim(string name) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new CajaException("El token no contiene los datos requeridos.", 401);

    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200)
    {
        try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); }
        catch (CajaException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); }
    }
}
