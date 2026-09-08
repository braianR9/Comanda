using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize]
[Route("api/tables")]
[Route("api/mesas")]
public class TablesController(TableService service) : ControllerBase
{
    [HttpGet] public async Task<ActionResult<ApiResponse<List<TableDto>>>> GetAll(int? sectorId, bool? active) { try { return Ok(ApiResponse<List<TableDto>>.Ok(await service.GetAllAsync(Company, Branch, sectorId, active))); } catch (TableException e) { return Error<List<TableDto>>(e); } }
    [HttpGet("{id:int}")] public async Task<ActionResult<ApiResponse<TableDto>>> Get(int id) { try { var value = await service.GetAsync(Company, Branch, id); return value == null ? NotFound(ApiResponse<TableDto>.NotFound("Mesa no encontrada.")) : Ok(ApiResponse<TableDto>.Ok(value)); } catch (TableException e) { return Error<TableDto>(e); } }
    [HttpPost] public async Task<ActionResult<ApiResponse<TableDto>>> Create(TableRequest request) { try { return StatusCode(201, ApiResponse<TableDto>.Ok(await service.CreateAsync(Company, Branch, request), 201)); } catch (TableException e) { return Error<TableDto>(e); } }
    [HttpPut("{id:int}")] public async Task<ActionResult<ApiResponse<TableDto>>> Update(int id, TableRequest request) { try { return Ok(ApiResponse<TableDto>.Ok(await service.UpdateAsync(Company, Branch, id, request))); } catch (TableException e) { return Error<TableDto>(e); } }
    [HttpPatch("{id:int}/status"), HttpPatch("{id:int}/estado")] public async Task<ActionResult<ApiResponse<TableDto>>> Status(int id, TableStatusRequest request) { try { return Ok(ApiResponse<TableDto>.Ok(await service.SetActiveAsync(Company, Branch, id, request.Active))); } catch (TableException e) { return Error<TableDto>(e); } }
    [HttpDelete("{id:int}")] public async Task<ActionResult<ApiResponse<object>>> Delete(int id) { try { await service.DeleteAsync(Company, Branch, id); return Ok(ApiResponse<object>.Ok(new { id, active = false })); } catch (TableException e) { return Error<object>(e); } }

    private int Company => Claim("id_empresa", "empresa");
    private int Branch => Claim("id_sucursal", "sucursal");
    private int Claim(string name, string label) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new TableException($"El token no contiene una {label} válida.", 401);
    private ActionResult<ApiResponse<T>> Error<T>(TableException e) => StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode));
}
