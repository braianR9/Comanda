using System.Security.Claims;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize, Route("api/sales")]
public class SalesController(OrderService service) : ControllerBase
{
    [HttpGet("active")] public async Task<ActionResult<ApiResponse<List<SaleDto>>>> Active() => Ok(ApiResponse<List<SaleDto>>.Ok(await service.ActiveAsync(Company, Branch)));
    [HttpGet("{id:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> Get(int id) { var v = await service.GetAsync(Company, Branch, id); return v == null ? NotFound(ApiResponse<SaleDto>.NotFound("Venta no encontrada.")) : Ok(ApiResponse<SaleDto>.Ok(v)); }
    [HttpGet("by-table/{tableId:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> ByTable(int tableId) { var v = await service.ByTableAsync(Company, Branch, tableId); return v == null ? NotFound(ApiResponse<SaleDto>.NotFound("La mesa no tiene una venta activa.")) : Ok(ApiResponse<SaleDto>.Ok(v)); }
    [HttpPost] public async Task<ActionResult<ApiResponse<SaleDto>>> Create(CreateSaleRequest r) => await Run(() => service.CreateAsync(Company, Branch, UserId, r), 201);
    [HttpPost("{id:int}/items")] public async Task<ActionResult<ApiResponse<SaleDto>>> AddItem(int id, SaleItemRequest r) => await Run(() => service.AddItemAsync(Company, Branch, id, r));
    [HttpPut("{id:int}/items/{itemId:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> UpdateItem(int id, int itemId, UpdateSaleItemRequest r) => await Run(() => service.UpdateItemAsync(Company, Branch, id, itemId, r));
    [HttpDelete("{id:int}/items/{itemId:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> DeleteItem(int id, int itemId, [FromQuery] long? version) => await Run(() => service.DeleteItemAsync(Company, Branch, id, itemId, version));
    [HttpPost("{id:int}/send-command")] public async Task<ActionResult<ApiResponse<CommandDto>>> SendCommand(int id, [FromQuery] long? version) => await Run(() => service.SendCommandAsync(Company, Branch, UserId, id, version), 201);
    [HttpGet("{id:int}/commands")] public async Task<ActionResult<ApiResponse<List<CommandDto>>>> Commands(int id) => await Run(() => service.CommandsAsync(Company, Branch, id));
    [HttpPost("{id:int}/discount")] public async Task<ActionResult<ApiResponse<SaleDto>>> Discount(int id, ApplyDiscountRequest r) => await Run(() => service.ApplyDiscountAsync(Company, Branch, id, r));
    [HttpDelete("{id:int}/discount")] public async Task<ActionResult<ApiResponse<SaleDto>>> RemoveDiscount(int id, [FromQuery] long? version) => await Run(() => service.RemoveDiscountAsync(Company, Branch, id, version));
    [HttpPut("{id:int}/price-list")] public async Task<ActionResult<ApiResponse<SaleDto>>> PriceList(int id, ChangeSalePriceListRequest r) => await Run(() => service.ChangePriceListAsync(Company, Branch, id, r));
    [HttpPost("{id:int}/payments")] public async Task<ActionResult<ApiResponse<SaleDto>>> Payments(int id, AddPaymentsRequest r) => await Run(() => service.AddPaymentsAsync(Company, Branch, UserId, id, r));
    [HttpPost("{id:int}/checkout")] public async Task<ActionResult<ApiResponse<SaleDto>>> Checkout(int id, [FromQuery] long? version) => await Run(() => service.CheckoutAsync(Company, Branch, UserId, id, version));
    [HttpPost("{id:int}/cancel")] public async Task<ActionResult<ApiResponse<SaleDto>>> Cancel(int id, [FromQuery] long? version) => await Run(() => service.CancelAsync(Company, Branch, id, version, UserId));
    [HttpPost("{id:int}/move-table")] public async Task<ActionResult<ApiResponse<SaleDto>>> Move(int id, MoveTableRequest r) => await Run(() => service.MoveAsync(Company, Branch, id, r));
    [HttpPost("{id:int}/join-table")] public async Task<ActionResult<ApiResponse<SaleDto>>> Join(int id, JoinTableRequest r) => await Run(() => service.JoinAsync(Company, Branch, id, r));
    [HttpGet("{id:int}/customer-ticket")] public async Task<ActionResult<ApiResponse<object>>> Ticket(int id) => await Run(() => service.CustomerTicketAsync(Company, Branch, id));
    [HttpGet("{id:int}/receipt")] public async Task<ActionResult<ApiResponse<object>>> Receipt(int id) => await Run(() => service.ReceiptAsync(Company, Branch, id));

    private int Company => Claim("id_empresa"); private int Branch => Claim("id_sucursal"); private int UserId => Claim(ClaimTypes.NameIdentifier);
    private int Claim(string name) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new SaleException("El token no contiene los datos requeridos.", 401);
    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200) { try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); } catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); } catch (DbUpdateConcurrencyException) { return Conflict(ApiResponse<T>.Fail("La venta fue modificada por otro usuario.", 409)); } }
}

// Compatibilidad temporal con el provider actual de Flutter. Los precios, total y userId se ignoran.
[ApiController, Authorize, Route("api/Orders")]
public class OrdersController(OrderService service) : ControllerBase
{
    [HttpGet] public async Task<ActionResult<ApiResponse<List<SaleDto>>>> Get() => Ok(ApiResponse<List<SaleDto>>.Ok(await service.ActiveAsync(Company, Branch)));
    [HttpGet("{id:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> Get(int id) { var v = await service.GetAsync(Company, Branch, id); return v == null ? NotFound(ApiResponse<SaleDto>.NotFound("Venta no encontrada.")) : Ok(ApiResponse<SaleDto>.Ok(v)); }
    [HttpPost]
    public async Task<ActionResult<ApiResponse<SaleDto>>> Create(LegacyOrderRequest r) => await Run(async () =>
    {
        var sale = await service.CreateAsync(Company, Branch, UserId, new CreateSaleRequest(r.TableId, null, r.Items.Select(i => new SaleItemRequest(i.ResolvedProductId, i.Quantity, i.Comment)).ToList()));
        await service.SendCommandAsync(Company, Branch, UserId, sale.Id, sale.Version);
        return (await service.GetAsync(Company, Branch, sale.Id))!;
    }, 201);
    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<SaleDto>>> Update(int id, LegacyOrderRequest r) => await Run(async () =>
    {
        var sale = await service.ReplaceItemsAsync(Company, Branch, id, r.Items.Select(i => new SaleItemRequest(i.ResolvedProductId, i.Quantity, i.Comment)));
        await service.SendCommandAsync(Company, Branch, UserId, sale.Id, sale.Version);
        return (await service.GetAsync(Company, Branch, sale.Id))!;
    });
    [HttpDelete("{id:int}")] public async Task<ActionResult<ApiResponse<SaleDto>>> Cancel(int id) => await Run(() => service.CancelAsync(Company, Branch, id, null, UserId));
    private int Company => Claim("id_empresa"); private int Branch => Claim("id_sucursal"); private int UserId => Claim(ClaimTypes.NameIdentifier);
    private int Claim(string name) => int.TryParse(User.FindFirstValue(name), out var id) ? id : throw new SaleException("El token no contiene los datos requeridos.", 401);
    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200) { try { var value = await action(); return StatusCode(code, ApiResponse<T>.Ok(value, code)); } catch (SaleException e) { return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode)); } }
}

[ApiController, Authorize, Route("api/sales-catalogs")]
public class SalesCatalogsController(AppDbContext db) : ControllerBase
{
    [HttpGet("payment-types")]
    public async Task<ActionResult<ApiResponse<object>>> PaymentTypes()
    {
        var company = Company;
        var values = await db.PaymentTypes.AsNoTracking()
            .Where(p => p.Activo && (p.IdEmpresa == null || p.IdEmpresa == company))
            .OrderBy(p => p.Nombre)
            .Select(p => new { id = p.Id, name = p.Nombre })
            .ToListAsync();
        return Ok(ApiResponse<object>.Ok(values));
    }

    [HttpGet("discounts")]
    public async Task<ActionResult<ApiResponse<List<DiscountCatalogDto>>>> Discounts([FromQuery] bool includeInactive = false)
    {
        var company = Company;
        var query = db.Discounts.AsNoTracking().Where(d => d.IdEmpresa == company);
        if (!includeInactive)
        {
            var now = DateTime.UtcNow;
            query = query.Where(d => d.Activo && (!d.VigenteDesde.HasValue || d.VigenteDesde <= now) && (!d.VigenteHasta.HasValue || d.VigenteHasta >= now));
        }
        var values = await query.OrderBy(d => d.Nombre).Select(d => DiscountDto(d)).ToListAsync();
        return Ok(ApiResponse<List<DiscountCatalogDto>>.Ok(values));
    }

    [HttpGet("discounts/{id:int}")]
    public async Task<ActionResult<ApiResponse<DiscountCatalogDto>>> Discount(int id)
    {
        var value = await db.Discounts.AsNoTracking().Where(d => d.Id == id && d.IdEmpresa == Company).Select(d => DiscountDto(d)).SingleOrDefaultAsync();
        return value is null ? NotFound(ApiResponse<DiscountCatalogDto>.NotFound("Descuento no encontrado.")) : Ok(ApiResponse<DiscountCatalogDto>.Ok(value));
    }

    [HttpPost("discounts")]
    public async Task<ActionResult<ApiResponse<DiscountCatalogDto>>> CreateDiscount(DiscountRequest request)
    {
        var validation = ValidateDiscount(request);
        if (validation is not null) return BadRequest(ApiResponse<DiscountCatalogDto>.Fail(validation));
        var name = request.Name.Trim();
        if (await db.Discounts.AnyAsync(d => d.IdEmpresa == Company && d.Nombre.ToLower() == name.ToLower()))
            return Conflict(ApiResponse<DiscountCatalogDto>.Fail("Ya existe un descuento con ese nombre.", 409));
        var value = new Discount { IdEmpresa = Company, Nombre = name, Descripcion = Clean(request.Description), Tipo = request.Type, Valor = request.Value, Activo = true, VigenteDesde = request.ValidFrom, VigenteHasta = request.ValidUntil };
        db.Discounts.Add(value); await db.SaveChangesAsync();
        return StatusCode(201, ApiResponse<DiscountCatalogDto>.Ok(DiscountDto(value), 201));
    }

    [HttpPut("discounts/{id:int}")]
    public async Task<ActionResult<ApiResponse<DiscountCatalogDto>>> UpdateDiscount(int id, DiscountRequest request)
    {
        var validation = ValidateDiscount(request);
        if (validation is not null) return BadRequest(ApiResponse<DiscountCatalogDto>.Fail(validation));
        var value = await db.Discounts.SingleOrDefaultAsync(d => d.Id == id && d.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<DiscountCatalogDto>.NotFound("Descuento no encontrado."));
        var name = request.Name.Trim();
        if (await db.Discounts.AnyAsync(d => d.IdEmpresa == Company && d.Id != id && d.Nombre.ToLower() == name.ToLower()))
            return Conflict(ApiResponse<DiscountCatalogDto>.Fail("Ya existe un descuento con ese nombre.", 409));
        value.Nombre = name; value.Descripcion = Clean(request.Description); value.Tipo = request.Type; value.Valor = request.Value; value.VigenteDesde = request.ValidFrom; value.VigenteHasta = request.ValidUntil;
        await db.SaveChangesAsync(); return Ok(ApiResponse<DiscountCatalogDto>.Ok(DiscountDto(value)));
    }

    [HttpPatch("discounts/{id:int}/status")]
    public async Task<ActionResult<ApiResponse<DiscountCatalogDto>>> DiscountStatus(int id, SalesCatalogStatusRequest request)
    {
        var value = await db.Discounts.SingleOrDefaultAsync(d => d.Id == id && d.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<DiscountCatalogDto>.NotFound("Descuento no encontrado."));
        value.Activo = request.Active; await db.SaveChangesAsync();
        return Ok(ApiResponse<DiscountCatalogDto>.Ok(DiscountDto(value)));
    }

    [HttpDelete("discounts/{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> DeleteDiscount(int id)
    {
        var value = await db.Discounts.SingleOrDefaultAsync(d => d.Id == id && d.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<object>.NotFound("Descuento no encontrado."));
        value.Activo = false; await db.SaveChangesAsync();
        return Ok(ApiResponse<object>.Ok(new { id, active = false }));
    }

    [HttpGet("cards")]
    public async Task<ActionResult<ApiResponse<List<CardDto>>>> Cards([FromQuery] bool includeInactive = false)
    {
        var company = Company;
        var query = db.Cards.AsNoTracking().Where(c => c.IdEmpresa == company);
        if (!includeInactive) query = query.Where(c => c.Activa);
        var values = await query.OrderBy(c => c.Nombre).Select(c => CardDto(c)).ToListAsync();
        return Ok(ApiResponse<List<CardDto>>.Ok(values));
    }

    [HttpGet("cards/{id:int}")]
    public async Task<ActionResult<ApiResponse<CardDto>>> Card(int id)
    {
        var value = await db.Cards.AsNoTracking().Where(c => c.Id == id && c.IdEmpresa == Company).Select(c => CardDto(c)).SingleOrDefaultAsync();
        return value is null ? NotFound(ApiResponse<CardDto>.NotFound("Tarjeta no encontrada.")) : Ok(ApiResponse<CardDto>.Ok(value));
    }

    [HttpPost("cards")]
    public async Task<ActionResult<ApiResponse<CardDto>>> CreateCard(CardRequest request)
    {
        request.AdjustmentType = NormalizeAdjustmentType(request.AdjustmentType);
        if (request.AdjustmentType == "SinAjuste") request.Percentage = 0;
        var validation = ValidateCard(request);
        if (validation is not null) return BadRequest(ApiResponse<CardDto>.Fail(validation));
        var name = request.Name.Trim();
        if (await db.Cards.AnyAsync(c => c.IdEmpresa == Company && c.Nombre.ToLower() == name.ToLower()))
            return Conflict(ApiResponse<CardDto>.Fail("Ya existe una tarjeta con ese nombre.", 409));
        var value = new Card { IdEmpresa = Company, Nombre = name, Descripcion = Clean(request.Description), TipoAjuste = request.AdjustmentType, Porcentaje = request.Percentage, Activa = true };
        db.Cards.Add(value); await db.SaveChangesAsync();
        return StatusCode(201, ApiResponse<CardDto>.Ok(CardDto(value), 201));
    }

    [HttpPut("cards/{id:int}")]
    public async Task<ActionResult<ApiResponse<CardDto>>> UpdateCard(int id, CardRequest request)
    {
        request.AdjustmentType = NormalizeAdjustmentType(request.AdjustmentType);
        if (request.AdjustmentType == "SinAjuste") request.Percentage = 0;
        var validation = ValidateCard(request);
        if (validation is not null) return BadRequest(ApiResponse<CardDto>.Fail(validation));
        var value = await db.Cards.SingleOrDefaultAsync(c => c.Id == id && c.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<CardDto>.NotFound("Tarjeta no encontrada."));
        var name = request.Name.Trim();
        if (await db.Cards.AnyAsync(c => c.IdEmpresa == Company && c.Id != id && c.Nombre.ToLower() == name.ToLower()))
            return Conflict(ApiResponse<CardDto>.Fail("Ya existe una tarjeta con ese nombre.", 409));
        value.Nombre = name; value.Descripcion = Clean(request.Description); value.TipoAjuste = request.AdjustmentType; value.Porcentaje = request.Percentage;
        await db.SaveChangesAsync(); return Ok(ApiResponse<CardDto>.Ok(CardDto(value)));
    }

    [HttpPatch("cards/{id:int}/status")]
    public async Task<ActionResult<ApiResponse<CardDto>>> CardStatus(int id, SalesCatalogStatusRequest request)
    {
        var value = await db.Cards.SingleOrDefaultAsync(c => c.Id == id && c.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<CardDto>.NotFound("Tarjeta no encontrada."));
        value.Activa = request.Active; await db.SaveChangesAsync();
        return Ok(ApiResponse<CardDto>.Ok(CardDto(value)));
    }

    [HttpDelete("cards/{id:int}")]
    public async Task<ActionResult<ApiResponse<object>>> DeleteCard(int id)
    {
        var value = await db.Cards.SingleOrDefaultAsync(c => c.Id == id && c.IdEmpresa == Company);
        if (value is null) return NotFound(ApiResponse<object>.NotFound("Tarjeta no encontrada."));
        value.Activa = false; await db.SaveChangesAsync();
        return Ok(ApiResponse<object>.Ok(new { id, active = false }));
    }

    private static DiscountCatalogDto DiscountDto(Discount d) => new(d.Id, d.Nombre, d.Descripcion, d.Tipo, d.Valor, d.Activo, d.VigenteDesde, d.VigenteHasta);
    private static CardDto CardDto(Card c) => new(c.Id, c.Nombre, c.Descripcion, c.TipoAjuste, c.Porcentaje, c.Activa);
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string? ValidateDiscount(DiscountRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name)) return "El nombre es obligatorio.";
        if (request.Type is not ("Porcentaje" or "Importe")) return "El tipo debe ser Porcentaje o Importe.";
        if (request.Value < 0 || request.Type == "Porcentaje" && request.Value > 100) return "El valor del descuento no es válido.";
        if (request.ValidFrom.HasValue && request.ValidUntil.HasValue && request.ValidUntil < request.ValidFrom) return "La fecha hasta no puede ser anterior a la fecha desde.";
        return null;
    }
    private static string? ValidateCard(CardRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name)) return "El nombre es obligatorio.";
        if (request.AdjustmentType is not ("SinAjuste" or "Descuento" or "Recargo")) return "El tipo de ajuste debe ser SinAjuste, Descuento o Recargo.";
        if (request.Percentage < 0 || request.Percentage > 100) return "El porcentaje debe estar entre 0 y 100.";
        if (request.AdjustmentType == "SinAjuste" && request.Percentage != 0) return "SinAjuste debe tener porcentaje 0.";
        if (request.AdjustmentType != "SinAjuste" && request.Percentage <= 0) return "Un descuento o recargo debe tener un porcentaje mayor que cero.";
        return null;
    }
    private static string NormalizeAdjustmentType(string? value)
    {
        var normalized = (value ?? string.Empty)
            .Trim()
            .Replace(" ", string.Empty)
            .Replace("_", string.Empty)
            .Replace("-", string.Empty)
            .ToLowerInvariant();
        return normalized switch
        {
            "sinajuste" => "SinAjuste",
            "descuento" => "Descuento",
            "recargo" => "Recargo",
            _ => value?.Trim() ?? string.Empty
        };
    }
    private int Company => int.TryParse(User.FindFirstValue("id_empresa"), out var id) ? id : throw new SaleException("El token no contiene una empresa válida.", 401);
}
