using System.Security.Claims;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/sucursales")]
public class SucursalesController(AppDbContext db, GoogleSheetsService sheets) : ControllerBase
{
    [HttpGet("google-sheet")]
    public async Task<ActionResult<ApiResponse<object>>> GetGoogleSheet()
    {
        try
        {
            var sheetId = await db.Sucursales.AsNoTracking()
                .Where(s => s.Id == Branch).Select(s => s.GoogleSheetId).SingleOrDefaultAsync();
            return Ok(ApiResponse<object>.Ok(new
            {
                sheetId,
                enabled = sheets.Enabled,
                serviceAccountEmail = sheets.ServiceAccountEmail,
            }));
        }
        catch (SaleException e)
        {
            return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode));
        }
    }

    [HttpPut("google-sheet")]
    public async Task<ActionResult<ApiResponse<object>>> SetGoogleSheet(GoogleSheetSettingsRequest request)
    {
        try
        {
            RequireAdmin();
            var sucursal = await db.Sucursales.SingleOrDefaultAsync(s => s.Id == Branch)
                ?? throw new SaleException("Sucursal no encontrada.", 404);
            sucursal.GoogleSheetId = GoogleSheetsService.ExtractSheetId(request.SheetIdOrUrl);
            await db.SaveChangesAsync();
            return Ok(ApiResponse<object>.Ok(new { sheetId = sucursal.GoogleSheetId }));
        }
        catch (SaleException e)
        {
            return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode));
        }
    }

    private int Branch => int.TryParse(User.FindFirstValue("id_sucursal"), out var id)
        ? id : throw new SaleException("Token inválido.", 401);

    private void RequireAdmin()
    {
        if (User.FindFirstValue("rol_nombre") != "ADMIN")
            throw new SaleException("No tenés permisos para esta acción.", 403);
    }
}
