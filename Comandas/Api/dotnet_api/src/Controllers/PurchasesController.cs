using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
namespace BarIceCreamShop.Api.Controllers;
[ApiController, Authorize]
public class PurchasesController(PurchaseService purchases, CompanySettingsService settings) : ControllerBase
{
    private int Company => int.Parse(User.FindFirstValue("id_empresa")!);
    private int Branch => int.Parse(User.FindFirstValue("id_sucursal")!);
    private int Actor => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private bool Manager => User.FindFirstValue("rol_nombre") is "ADMIN" or "CAJA" or "ENCARGADO";
    private async Task<IActionResult> Run(Func<Task<object>> action, bool manager = false)
    {
        if (manager && !Manager) return StatusCode(403, ApiResponse<object>.Fail("Requiere ADMIN o CAJA.", 403));
        try { return Ok(ApiResponse<object>.Ok(await action())); }
        catch (PurchaseException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); }
        catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); }
    }
    [HttpGet("api/company-settings")] public Task<IActionResult> Settings() => Run(() => settings.GetAsync(Company));
    [HttpPut("api/company-settings")] public Task<IActionResult> SaveSettings(CompanySettingsRequest r) => Run(() => settings.SaveAsync(Company, Actor, r), true);
    [HttpGet("api/suppliers")] public Task<IActionResult> Suppliers() => Run(async () => await purchases.SuppliersAsync(Company));
    [HttpGet("api/suppliers/{id:int}")] public Task<IActionResult> Supplier(int id) => Run(() => purchases.SupplierAsync(Company, id));
    [HttpPost("api/suppliers")] public Task<IActionResult> NewSupplier(SupplierRequest r) => Run(async () => await purchases.SaveSupplierAsync(Company, null, r), true);
    [HttpPut("api/suppliers/{id:int}")] public Task<IActionResult> SaveSupplier(int id, SupplierRequest r) => Run(async () => await purchases.SaveSupplierAsync(Company, id, r), true);
    [HttpGet("api/purchases")] public Task<IActionResult> List(string? status, int page = 1) => Run(() => purchases.ListAsync(Company, Branch, status, page));
    [HttpGet("api/purchases/{id:int}")] public Task<IActionResult> Get(int id) => Run(() => purchases.GetAsync(Company, Branch, id));
    [HttpPost("api/purchases")] public Task<IActionResult> Create(PurchaseRequest r) => Run(() => purchases.SaveAsync(Company, Branch, Actor, null, r));
    [HttpPut("api/purchases/{id:int}")] public Task<IActionResult> Update(int id, PurchaseRequest r) => Run(() => purchases.SaveAsync(Company, Branch, Actor, id, r));
    [HttpPost("api/purchases/{id:int}/control")] public Task<IActionResult> Control(int id, PurchaseActionRequest r) => Run(() => purchases.ControlAsync(Company, Branch, Actor, id, r), true);
    [HttpPost("api/purchases/{id:int}/cancel")] public Task<IActionResult> Cancel(int id, PurchaseActionRequest r) => Run(() => purchases.CancelAsync(Company, Branch, Actor, id, r), true);
}
