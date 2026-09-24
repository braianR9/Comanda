using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/listas-precios")]
public class PriceListsController(PriceListService service) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<PriceListDto>>>> GetAll() =>
        await Run(() => service.ListAsync(Company));

    [HttpPost]
    public async Task<ActionResult<ApiResponse<PriceListDto>>> Create(CreatePriceListRequest request) =>
        await Run(() => service.CreateAsync(Company, request), 201);

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<PriceListDto>>> Rename(int id, UpdatePriceListRequest request) =>
        await Run(() => service.RenameAsync(Company, id, request));

    [HttpPatch("{id:int}/estado")]
    public async Task<ActionResult<ApiResponse<PriceListDto>>> SetStatus(int id, PriceListStatusRequest request) =>
        await Run(() => service.SetActiveAsync(Company, id, request.Activa));

    [HttpPatch("{id:int}/predeterminada")]
    public async Task<ActionResult<ApiResponse<PriceListDto>>> SetDefault(int id) =>
        await Run(() => service.SetDefaultAsync(Company, id));

    [HttpDelete("{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(int id) =>
        await Run(async () => { await service.DeleteAsync(Company, id); return (object)new { id }; });

    [HttpGet("{id:int}/precios")]
    public async Task<ActionResult<ApiResponse<PagedResult<ProductPriceDto>>>> GetPrices(
        int id, [FromQuery] int? idRubro, [FromQuery] int? idSubRubro, [FromQuery] string? texto,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 30) =>
        await Run(() => service.GetPricesAsync(Company, id, idRubro, idSubRubro, texto, page, pageSize));

    [HttpPut("{id:int}/precios/{productId:int}")]
    public async Task<ActionResult<ApiResponse<ProductPriceDto>>> SetPrice(int id, int productId, SetProductPriceRequest request) =>
        await Run(() => service.SetPriceAsync(Company, id, productId, request.Precio));

    [HttpPost("{id:int}/precios/vista-previa-masiva")]
    public async Task<ActionResult<ApiResponse<List<BulkPricePreviewItem>>>> PreviewBulk(int id, BulkPriceOperationRequest request) =>
        await Run(() => service.PreviewBulkAsync(Company, id, request));

    [HttpPost("{id:int}/precios/aplicar-masivo")]
    public async Task<ActionResult<ApiResponse<object>>> ApplyBulk(int id, BulkPriceOperationRequest request) =>
        await Run(async () => (object)new { actualizados = await service.ApplyBulkAsync(Company, id, request) });

    private int Company => int.TryParse(User.FindFirstValue("id_empresa"), out var value) ? value : throw new PriceListException("El token no contiene una empresa válida.", 401);

    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200)
    {
        try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); }
        catch (PriceListException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); }
    }
}
