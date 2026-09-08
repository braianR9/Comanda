using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize]
[Route("api/sectors")]
[Route("api/sectores")]
public class SectorsController(SectorService service) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<SectorDto>>>> GetAll([FromQuery] bool? active, [FromQuery] string? text)
    { try { return Ok(ApiResponse<List<SectorDto>>.Ok(await service.GetAllAsync(CompanyId, active, text))); } catch (SectorException e) { return Error<List<SectorDto>>(e); } }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<SectorDto>>> Get(int id)
    {
        try { var sector = await service.GetAsync(CompanyId, id); return sector == null ? NotFound(ApiResponse<SectorDto>.NotFound("Sector no encontrado.")) : Ok(ApiResponse<SectorDto>.Ok(sector)); }
        catch (SectorException e) { return Error<SectorDto>(e); }
    }

    [HttpPost]
    public async Task<ActionResult<ApiResponse<SectorDto>>> Create(SectorRequest request)
    { try { return StatusCode(201, ApiResponse<SectorDto>.Ok(await service.CreateAsync(CompanyId, request), 201)); } catch (SectorException e) { return Error<SectorDto>(e); } }

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<SectorDto>>> Update(int id, SectorRequest request)
    { try { return Ok(ApiResponse<SectorDto>.Ok(await service.UpdateAsync(CompanyId, id, request))); } catch (SectorException e) { return Error<SectorDto>(e); } }

    [HttpPatch("{id:int}/status")]
    [HttpPatch("{id:int}/estado")]
    public async Task<ActionResult<ApiResponse<SectorDto>>> Status(int id, SectorStatusRequest request)
    { try { return Ok(ApiResponse<SectorDto>.Ok(await service.SetStatusAsync(CompanyId, id, request.Active))); } catch (SectorException e) { return Error<SectorDto>(e); } }

    [HttpPut("order")]
    [HttpPut("orden")]
    public async Task<ActionResult<ApiResponse<List<SectorDto>>>> Reorder(ReorderSectorsRequest request)
    { try { return Ok(ApiResponse<List<SectorDto>>.Ok(await service.ReorderAsync(CompanyId, request))); } catch (SectorException e) { return Error<List<SectorDto>>(e); } }

    [HttpDelete("{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(int id)
    { try { await service.DeleteAsync(CompanyId, id); return Ok(ApiResponse<object>.Ok(new { id, active = false })); } catch (SectorException e) { return Error<object>(e); } }

    private int CompanyId => int.TryParse(User.FindFirstValue("id_empresa"), out var id) ? id : throw new SectorException("El token no contiene una empresa válida.", 401);
    private ActionResult<ApiResponse<T>> Error<T>(SectorException e) => StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode));
}
