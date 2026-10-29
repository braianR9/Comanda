using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize(Policy = SalePermissions.CashierPolicy)]
public sealed class SaleVoidsController(SaleVoidService service) : ControllerBase
{
    private int Claim(string name) => int.Parse(User.FindFirstValue(name)!);
    [HttpPost("api/sales/{id:int}/void")]
    public async Task<IActionResult> Void(int id, VoidSaleRequest request)
    {
        try { return Ok(ApiResponse<object>.Ok(await service.VoidAsync(Claim("id_empresa"), Claim("id_sucursal"), Claim(ClaimTypes.NameIdentifier), id, request))); }
        catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); }
    }
    [HttpGet("api/sales/voids")]
    public async Task<object> List(int page = 1) => ApiResponse<object>.Ok(await service.ListAsync(Claim("id_empresa"), Claim("id_sucursal"), page));
}
