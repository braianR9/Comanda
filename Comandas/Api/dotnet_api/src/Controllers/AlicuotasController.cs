using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/alicuotas")]
public class AlicuotasController(CatalogosService service) : CatalogControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<AlicuotaDto>>>> GetAll(bool? activo)
    { try { return Ok(ApiResponse<List<AlicuotaDto>>.Ok(await service.GetAlicuotasAsync(CompanyId, activo))); } catch (CatalogoException e) { return CatalogError<List<AlicuotaDto>>(e); } }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<AlicuotaDto>>> Get(int id)
    { try { var value = await service.GetAlicuotaAsync(CompanyId, id); return value == null ? NotFound(ApiResponse<AlicuotaDto>.NotFound("Alícuota no encontrada.")) : Ok(ApiResponse<AlicuotaDto>.Ok(value)); } catch (CatalogoException e) { return CatalogError<AlicuotaDto>(e); } }

    [HttpPost]
    public async Task<ActionResult<ApiResponse<AlicuotaDto>>> Create(AlicuotaRequest request)
    { try { return StatusCode(201, ApiResponse<AlicuotaDto>.Ok(await service.CreateAlicuotaAsync(CompanyId, request), 201)); } catch (CatalogoException e) { return CatalogError<AlicuotaDto>(e); } }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<AlicuotaDto>>> Update(int id, AlicuotaRequest request)
    { try { return Ok(ApiResponse<AlicuotaDto>.Ok(await service.UpdateAlicuotaAsync(CompanyId, id, request))); } catch (CatalogoException e) { return CatalogError<AlicuotaDto>(e); } }

    [HttpPatch("{id:int}/estado")]
    public async Task<ActionResult<ApiResponse<object>>> Status(int id, CatalogStatusRequest request)
    { try { await service.SetAlicuotaStatusAsync(CompanyId, id, request.Activo); return Ok(ApiResponse<object>.Ok(new { id, request.Activo })); } catch (CatalogoException e) { return CatalogError<object>(e); } }

    [HttpDelete("{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(int id)
    { try { await service.DeleteAlicuotaAsync(CompanyId, id); return Ok(ApiResponse<object>.Ok(new { id })); } catch (CatalogoException e) { return CatalogError<object>(e); } }
}
