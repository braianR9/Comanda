using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/reports")]
public class ReportsController(ReportsService service) : ControllerBase
{
    [HttpGet("sales-detail")]
    public async Task<ActionResult<ApiResponse<SalesDetailResultDto>>> SalesDetail(
        DateTime? from, DateTime? to, bool rangoHorario, TimeSpan? horaDesde, TimeSpan? horaHasta,
        int? rubroId, int? subRubroId, int? sectorId, int? numeroPedido)
    {
        var filter = BuildFilter(from, to, rangoHorario, horaDesde, horaHasta, rubroId, subRubroId, sectorId, numeroPedido);
        return Ok(ApiResponse<SalesDetailResultDto>.Ok(await service.SalesDetailAsync(Company, Branch, filter)));
    }

    [HttpGet("sales-detail/export")]
    public async Task<IActionResult> ExportSalesDetail(
        DateTime? from, DateTime? to, bool rangoHorario, TimeSpan? horaDesde, TimeSpan? horaHasta,
        int? rubroId, int? subRubroId, int? sectorId, int? numeroPedido)
    {
        var filter = BuildFilter(from, to, rangoHorario, horaDesde, horaHasta, rubroId, subRubroId, sectorId, numeroPedido);
        var bytes = await service.ExportSalesDetailXlsxAsync(Company, Branch, filter);
        return File(bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "listado-ventas.xlsx");
    }

    private static SalesDetailFilter BuildFilter(
        DateTime? from, DateTime? to, bool rangoHorario, TimeSpan? horaDesde, TimeSpan? horaHasta,
        int? rubroId, int? subRubroId, int? sectorId, int? numeroPedido) => new()
        {
            From = from,
            To = to,
            UseTimeRange = rangoHorario,
            TimeFrom = horaDesde,
            TimeTo = horaHasta,
            RubroId = rubroId,
            SubRubroId = subRubroId,
            SectorId = sectorId,
            OrderNumber = numeroPedido,
        };

    private int Company => Claim("id_empresa", "empresa");
    private int Branch => Claim("id_sucursal", "sucursal");
    private int Claim(string name, string label) => int.TryParse(User.FindFirstValue(name), out var id)
        ? id : throw new SaleException($"El token no contiene una {label} válida.", 401);
}
