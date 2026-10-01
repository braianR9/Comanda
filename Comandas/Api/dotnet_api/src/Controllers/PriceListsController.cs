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
        await Run(() => service.SetPriceAsync(Company, id, productId, request.Precio, Actor));

    [HttpPost("{id:int}/precios/vista-previa-masiva")]
    public async Task<ActionResult<ApiResponse<List<BulkPricePreviewItem>>>> PreviewBulk(int id, BulkPriceOperationRequest request) =>
        await Run(() => service.PreviewBulkAsync(Company, id, request));

    [HttpPost("{id:int}/precios/aplicar-masivo")]
    public async Task<ActionResult<ApiResponse<object>>> ApplyBulk(int id, BulkPriceOperationRequest request) =>
        await Run(async () => (object)new { actualizados = await service.ApplyBulkAsync(Company, id, request, Actor) });

    [HttpPut("planilla")]
    public async Task<ActionResult<ApiResponse<object>>> SaveGrid(SavePriceGridRequest request) =>
        await Run(async () => (object)new { actualizados = await service.SaveGridAsync(Company, request.Cambios, Actor) });

    [HttpGet("historial")]
    public async Task<ActionResult<ApiResponse<object>>> History([FromQuery] int page = 1) =>
        await Run(() => service.HistoryAsync(Company, page));

    [HttpGet("historial/{batch:guid}")]
    public async Task<ActionResult<ApiResponse<List<PriceHistory>>>> HistoryDetails(Guid batch) =>
        await Run(() => service.HistoryDetailsAsync(Company, batch));

    [HttpPost("historial/{batch:guid}/revertir")]
    public async Task<ActionResult<ApiResponse<object>>> Revert(Guid batch) =>
        await Run(async () => (object)new { actualizados = await service.RevertAsync(Company, batch, Actor) });

    [HttpGet("{id:int}/reglas")]
    public async Task<ActionResult<ApiResponse<List<ScheduledPriceRule>>>> Rules(int id) =>
        await Run(() => service.RulesAsync(Company, id));

    [HttpPost("{id:int}/reglas")]
    public async Task<ActionResult<ApiResponse<ScheduledPriceRule>>> CreateRule(int id, SaveScheduledPriceRuleRequest request) =>
        await Run(() => service.SaveRuleAsync(Company, id, null, request, Actor), 201);

    [HttpPut("{id:int}/reglas/{ruleId:int}")]
    public async Task<ActionResult<ApiResponse<ScheduledPriceRule>>> UpdateRule(int id, int ruleId, SaveScheduledPriceRuleRequest request) =>
        await Run(() => service.SaveRuleAsync(Company, id, ruleId, request, Actor));

    [HttpPost("consulta-precios")]
    public async Task<ActionResult<ApiResponse<List<EffectivePriceDto>>>> Quote(PriceQuoteRequest request) =>
        await Run(() => service.QuotePricesAsync(Company, Branch, request));

    private int Branch => int.TryParse(User.FindFirstValue("id_sucursal"), out var value) ? value : throw new PriceListException("El token no contiene una sucursal válida.", 401);

    private string Actor => User.FindFirstValue(ClaimTypes.Email) ?? User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "Usuario";
    private int Company => int.TryParse(User.FindFirstValue("id_empresa"), out var value) ? value : throw new PriceListException("El token no contiene una empresa válida.", 401);

    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200)
    {
        try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); }
        catch (Exception e) when ((e is Npgsql.PostgresException pg && (pg.SqlState == "40001" || pg.SqlState == "23505"))
            || (e.InnerException is Npgsql.PostgresException inner && (inner.SqlState == "40001" || inner.SqlState == "23505")))
        { return StatusCode(409, ApiResponse<T>.Fail("Los precios cambiaron durante la operación. Recargá y volvé a intentarlo.", 409)); }
        catch (PriceListException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); }
    }
}
