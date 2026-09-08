using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/printers")]
public sealed class PrintersController(PrinterConfigurationService service) : ControllerBase
{
    [HttpGet] public async Task<ActionResult<ApiResponse<List<PrinterConfigurationDto>>>> List([FromQuery] bool includeInactive = false) => Ok(ApiResponse<List<PrinterConfigurationDto>>.Ok(await service.ListAsync(Company, Branch, includeInactive)));
    [HttpGet("{id:int}")] public async Task<ActionResult<ApiResponse<PrinterConfigurationDto>>> Get(int id) { var value = await service.GetAsync(Company, Branch, id); return value is null ? NotFound(ApiResponse<PrinterConfigurationDto>.NotFound("Impresora no encontrada.")) : Ok(ApiResponse<PrinterConfigurationDto>.Ok(value)); }
    [HttpPost] public async Task<ActionResult<ApiResponse<PrinterConfigurationDto>>> Create(PrinterConfigurationRequest request) => await Run(() => service.CreateAsync(Company, Branch, request), 201);
    [HttpPut("{id:int}")] public async Task<ActionResult<ApiResponse<PrinterConfigurationDto>>> Update(int id, PrinterConfigurationRequest request) => await Run(() => service.UpdateAsync(Company, Branch, id, request));
    [HttpPatch("{id:int}/status")] public async Task<ActionResult<ApiResponse<PrinterConfigurationDto>>> Status(int id, PrinterStatusRequest request) => await Run(() => service.SetStatusAsync(Company, Branch, id, request.Active));
    [HttpDelete("{id:int}")] public async Task<ActionResult<ApiResponse<PrinterConfigurationDto>>> Delete(int id) => await Run(() => service.SetStatusAsync(Company, Branch, id, false));
    [HttpPost("{id:int}/test")] public async Task<ActionResult<ApiResponse<object>>> Test(int id, CancellationToken cancellationToken)
    { try { await service.TestAsync(Company, Branch, id, cancellationToken); return Ok(ApiResponse<object>.Ok(new { message = "Prueba enviada correctamente." })); } catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); } catch (Exception e) { return StatusCode(500, ApiResponse<object>.ServerError(e.Message)); } }
    private int Company => Claim("id_empresa"); private int Branch => Claim("id_sucursal");
    private int Claim(string name) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new SaleException("El token no contiene los datos requeridos.", 401);
    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200) { try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); } catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); } }
}
