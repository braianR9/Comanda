using System.Data;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace BarIceCreamShop.Api.Services;

public sealed class SaleException(string message, int statusCode = 400) : Exception(message) { public int StatusCode { get; } = statusCode; }

public class OrderService(AppDbContext context, IConfiguration configuration, StockMovementService stockMovements)
{
    private static readonly string[] ActiveStates = ["Abierta", "EnPedido", "PedidoEnviado", "ConCambios"];

    public async Task<List<SaleDto>> ActiveAsync(int company, int branch) =>
        (await BaseQuery().Where(v => v.IdEmpresa == company && v.IdSucursal == branch && ActiveStates.Contains(v.Estado)).ToListAsync()).Select(Map).ToList();

    public async Task<SaleDto?> GetAsync(int company, int branch, int id)
    { var value = await BaseQuery().FirstOrDefaultAsync(v => v.Id == id && v.IdEmpresa == company && v.IdSucursal == branch); return value == null ? null : Map(value); }

    public async Task<SaleDto?> ByTableAsync(int company, int branch, int tableId)
    {
        var value = await BaseQuery().FirstOrDefaultAsync(v => v.IdEmpresa == company && v.IdSucursal == branch && ActiveStates.Contains(v.Estado) && (v.TableId == tableId || v.JoinedTables.Any(j => j.TableId == tableId)));
        return value == null ? null : Map(value);
    }

    public async Task<SaleDto> CreateAsync(int company, int branch, int user, CreateSaleRequest request)
    {
        if (request.Items == null || request.Items.Count == 0) throw new SaleException("La venta se abre al agregar el primer producto.");
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable);
        await ValidateFreeTable(company, branch, request.TableId, null);
        var sale = new Order { IdEmpresa = company, IdSucursal = branch, Numero = await NextNumber(company, false, tx), TableId = request.TableId, MozoId = request.WaiterId, Estado = "EnPedido", FechaApertura = DateTime.UtcNow, UsuarioId = user, Version = 1 };
        (await context.Tables.FirstAsync(t => t.Id == request.TableId)).Status = "Ocupada";
        context.Orders.Add(sale); await context.SaveChangesAsync();
        foreach (var item in request.Items) await AddOrMergeItem(sale, item.ProductId, item.Quantity, item.Comment);
        Recalculate(sale); await context.SaveChangesAsync(); await tx.CommitAsync(); return (await GetAsync(company, branch, sale.Id))!;
    }

    public async Task<SaleDto> AddItemAsync(int company, int branch, int id, SaleItemRequest request)
    {
        var sale = await Editable(company, branch, id); await AddOrMergeItem(sale, request.ProductId, request.Quantity, request.Comment);
        Changed(sale); Recalculate(sale); await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> ReplaceItemsAsync(int company, int branch, int id, IEnumerable<SaleItemRequest> requests)
    {
        var sale = await Editable(company, branch, id); context.Set<OrderItem>().RemoveRange(sale.Items); sale.Items.Clear();
        foreach (var item in requests) await AddOrMergeItem(sale, item.ProductId, item.Quantity, item.Comment);
        Changed(sale); Recalculate(sale); await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> UpdateItemAsync(int company, int branch, int id, int itemId, UpdateSaleItemRequest request)
    {
        var sale = await Editable(company, branch, id, request.Version); var item = sale.Items.FirstOrDefault(i => i.Id == itemId) ?? throw new SaleException("Renglón no encontrado.", 404);
        item.Quantity = request.Quantity; item.Comment = CleanComment(request.Comment); item.Subtotal = Money(item.UnitPrice * item.Quantity); item.FechaModificacion = DateTime.UtcNow;
        Changed(sale); Recalculate(sale); await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> DeleteItemAsync(int company, int branch, int id, int itemId, long? version)
    {
        var sale = await Editable(company, branch, id, version); var item = sale.Items.FirstOrDefault(i => i.Id == itemId) ?? throw new SaleException("Renglón no encontrado.", 404);
        if (sale.Items.Count == 1 && sale.Commands.Count > 0)
            throw new SaleException("Para quitar el último producto de un pedido enviado, usá Anular pedido.", 409);

        context.Set<OrderItem>().Remove(item);
        sale.Items.Remove(item);
        Recalculate(sale);

        if (sale.Items.Count == 0)
        {
            sale.Estado = "Cancelada";
            sale.FechaCierre = DateTime.UtcNow;
            sale.Version++;
            sale.Table.Status = "Libre";
            foreach (var joined in sale.JoinedTables)
                (await context.Tables.FirstAsync(t => t.Id == joined.TableId)).Status = "Libre";
        }
        else
        {
            Changed(sale);
        }

        await context.SaveChangesAsync();
        return (await GetAsync(company, branch, id))!;
    }

    public async Task<CommandDto> SendCommandAsync(int company, int branch, int user, int id, long? version)
    {
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable);
        var sale = await Editable(company, branch, id, version); var previous = sale.Commands.OrderBy(c => c.Fecha).ToList();
        var sent = previous.SelectMany(c => c.Lines.Select(l => new { c.Fecha, Line = l })).GroupBy(x => x.Line.ProductId).ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.Fecha).First().Line.CurrentQuantity);
        var lastComments = previous.SelectMany(c => c.Lines.Select(l => new { c.Fecha, Line = l })).GroupBy(x => x.Line.ProductId).ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.Fecha).First().Line.Comment);
        var current = sale.Items.ToDictionary(i => i.ProductId); var productIds = sent.Keys.Union(current.Keys).ToList(); var lines = new List<KitchenCommandLine>();
        foreach (var productId in productIds)
        {
            current.TryGetValue(productId, out var item); var currentQty = item?.Quantity ?? 0; var oldQty = sent.GetValueOrDefault(productId); var comment = item?.Comment; var commentChanged = lastComments.GetValueOrDefault(productId) != comment;
            if (currentQty != oldQty || commentChanged) lines.Add(new KitchenCommandLine { ProductId = productId, ProductName = item?.ProductName ?? previous.SelectMany(c => c.Lines).Last(l => l.ProductId == productId).ProductName, QuantityDelta = currentQty - oldQty, CurrentQuantity = currentQty, Comment = comment });
        }
        if (lines.Count == 0) throw new SaleException("No hay cambios para enviar a comanda.", 409);
        var command = new KitchenCommand { IdEmpresa = company, Numero = await NextNumber(company, true, tx), OrderId = id, TableId = sale.TableId, MozoId = sale.MozoId, Tipo = previous.Count == 0 ? "Inicial" : "Modificación", Fecha = DateTime.UtcNow, UsuarioId = user, Lines = lines };
        context.KitchenCommands.Add(command); sale.Estado = "PedidoEnviado"; sale.Version++; await context.SaveChangesAsync(); await tx.CommitAsync();
        return new CommandDto(command.Id, command.Numero, command.Tipo, command.Fecha, command.TableId, command.MozoId, lines.Select(l => new CommandLineDto(l.ProductId, l.ProductName, l.QuantityDelta, l.CurrentQuantity, l.Comment)).ToList());
    }

    public async Task<List<CommandDto>> CommandsAsync(int company, int branch, int id)
    {
        await Require(company, branch, id);
        return await context.KitchenCommands.AsNoTracking().Where(c => c.OrderId == id).OrderBy(c => c.Fecha).Select(c => new CommandDto(c.Id, c.Numero, c.Tipo, c.Fecha, c.TableId, c.MozoId, c.Lines.Select(l => new CommandLineDto(l.ProductId, l.ProductName, l.QuantityDelta, l.CurrentQuantity, l.Comment)).ToList())).ToListAsync();
    }

    public async Task<SaleDto> ApplyDiscountAsync(int company, int branch, int id, ApplyDiscountRequest request)
    {
        var sale = await Editable(company, branch, id, request.Version); string name; string type; decimal value;
        if (request.DiscountId.HasValue)
        {
            var discount = await context.Discounts.AsNoTracking().FirstOrDefaultAsync(d => d.Id == request.DiscountId && d.IdEmpresa == company && d.Activo && (!d.VigenteDesde.HasValue || d.VigenteDesde <= DateTime.UtcNow) && (!d.VigenteHasta.HasValue || d.VigenteHasta >= DateTime.UtcNow)) ?? throw new SaleException("Descuento no encontrado o fuera de vigencia.", 404);
            name = discount.Nombre; type = discount.Tipo; value = discount.Valor;
        }
        else { name = string.IsNullOrWhiteSpace(request.Name) ? "Descuento manual" : request.Name.Trim(); type = request.Type; value = request.Value; }
        ValidateDiscount(type, value); sale.DescuentoId = request.DiscountId; sale.DescuentoNombre = name; sale.DescuentoTipo = type; sale.DescuentoValor = value; sale.Version++; Recalculate(sale);
        await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> RemoveDiscountAsync(int company, int branch, int id, long? version)
    { var sale = await Editable(company, branch, id, version); sale.DescuentoId = null; sale.DescuentoNombre = sale.DescuentoTipo = null; sale.DescuentoValor = null; sale.Version++; Recalculate(sale); await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!; }

    public async Task<SaleDto> AddPaymentsAsync(int company, int branch, int user, int id, AddPaymentsRequest request)
    {
        var sale = await Editable(company, branch, id, request.Version, allowPayments: true);
        if (sale.Commands.Count == 0 || HasPendingKitchenChanges(sale)) throw new SaleException("Debe enviar la comanda y sus cambios antes de cobrar.", 409);
        if (request.Payments.Count == 0) throw new SaleException("Seleccioná un medio de pago.");
        var pending = new List<SalePayment>();
        foreach (var payment in request.Payments)
        {
            if (payment.CardId.HasValue == payment.PaymentTypeId.HasValue)
                throw new SaleException("Indicá un único medio de pago.");
            var saved = new SalePayment { Fecha = DateTime.UtcNow, UsuarioId = user, Reference = payment.Reference?.Trim() };
            if (payment.CardId.HasValue)
            {
                var card = await context.Cards.AsNoTracking().SingleOrDefaultAsync(c => c.Id == payment.CardId && c.IdEmpresa == company && c.Activa)
                    ?? throw new SaleException("El medio de pago ya no está disponible. Revisá el maestro de pagos.", 409);
                if (!payment.BaseAmount.HasValue) throw new SaleException("Falta el importe base del pago.");
                var calculation = PaymentCalculation.Calculate(payment.BaseAmount.Value, card.TipoAjuste, card.Porcentaje);
                if (Money(payment.Amount) != calculation.Total)
                    throw new SaleException("El porcentaje del medio de pago cambió. Revisá el total y volvé a confirmar.", 409);
                saved.CardId = card.Id; saved.PaymentTypeName = card.Nombre;
                saved.BaseAmount = calculation.Base; saved.AdjustmentAmount = calculation.Adjustment;
                saved.Amount = calculation.Total; saved.AdjustmentType = card.TipoAjuste; saved.Percentage = card.Porcentaje;
            }
            else
            {
                // Compatibilidad con clientes anteriores, sin confundir sus IDs con los del maestro.
                var type = await context.PaymentTypes.AsNoTracking().FirstOrDefaultAsync(p => p.Id == payment.PaymentTypeId && p.Activo && (p.IdEmpresa == null || p.IdEmpresa == company))
                    ?? throw new SaleException("Tipo de cobro no válido.", 404);
                if (Money(payment.Amount) <= 0) throw new SaleException("El importe debe ser mayor que cero.");
                saved.PaymentTypeId = type.Id; saved.PaymentTypeName = type.Nombre;
                saved.Amount = Money(payment.Amount); saved.BaseAmount = saved.Amount;
            }
            pending.Add(saved);
        }
        var covered = sale.Payments.Sum(p => p.BaseAmount ?? p.Amount);
        var basis = Money(sale.Subtotal - sale.ImporteDescuento);
        if (Money(covered + pending.Sum(p => p.BaseAmount ?? p.Amount)) > basis)
            throw new SaleException("Los importes asignados superan el saldo de la cuenta.");
        sale.Payments.AddRange(pending);
        sale.Total = basis + sale.Payments.Sum(p => p.AdjustmentAmount);
        sale.Version++;
        await context.SaveChangesAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> CheckoutAsync(int company, int branch, int user, int id, long? version)
    {
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable); var sale = await Editable(company, branch, id, version, allowPayments: true);
        if (sale.Commands.Count == 0 || HasPendingKitchenChanges(sale)) throw new SaleException("Debe enviar la comanda y sus cambios antes de cobrar.", 409);
        if (Money(sale.Payments.Sum(p => p.Amount)) != sale.Total) throw new SaleException("La suma de los pagos debe coincidir exactamente con el total.", 409);
        await stockMovements.ApplySaleAsync(sale, user);
        sale.Estado = "Finalizada"; sale.FechaCierre = DateTime.UtcNow; sale.UsuarioCobroId = user; sale.Version++; sale.Table.Status = "Libre";
        foreach (var joined in sale.JoinedTables) { var table = await context.Tables.FirstAsync(t => t.Id == joined.TableId); table.Status = "Libre"; }
        context.PrintJobs.Add(new PrintJob
        {
            OrderId = sale.Id,
            PrinterId = configuration["PrinterSettings:QueueName"] ?? "Printer_POS_80C",
            CreatedAt = DateTime.UtcNow,
            Status = "Pendiente",
            JobType = "TicketVenta"
        });
        if (await context.Sucursales.AsNoTracking().AnyAsync(s => s.Id == branch && s.GoogleSheetId != null))
            context.GoogleSheetJobs.Add(new GoogleSheetJob
            {
                OrderId = sale.Id,
                BranchId = branch,
                Status = "Pendiente",
                CreatedAt = DateTime.UtcNow,
            });
        await context.SaveChangesAsync(); await tx.CommitAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> CancelAsync(int company, int branch, int id, long? version, int? userId = null)
    {
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable);
        var sale = await Editable(company, branch, id, version);
        if (sale.Payments.Count > 0) throw new SaleException("No se puede anular una venta con pagos registrados.", 409);
        var sentLines = sale.Commands.OrderBy(c => c.Fecha).ThenBy(c => c.Id)
            .SelectMany(c => c.Lines).GroupBy(line => line.ProductId)
            .Select(group => group.Last()).Where(line => line.CurrentQuantity > 0).ToList();
        if (sentLines.Count > 0)
        {
            // Se conservan los productos de la venta para su historial y se
            // registra una baja de todo lo que efectivamente recibió cocina.
            var command = new KitchenCommand {
                IdEmpresa = company, Numero = await NextNumber(company, true, tx),
                OrderId = sale.Id, TableId = sale.TableId, MozoId = sale.MozoId,
                Tipo = "Modificación", Fecha = DateTime.UtcNow, UsuarioId = userId ?? sale.UsuarioId,
                Lines = sentLines.Select(line => new KitchenCommandLine {
                    ProductId = line.ProductId, ProductName = line.ProductName,
                    QuantityDelta = -line.CurrentQuantity, CurrentQuantity = 0,
                    Comment = "ANULACIÓN DEL PEDIDO"
                }).ToList()
            };
            context.KitchenCommands.Add(command);
            context.PrintJobs.Add(new PrintJob {
                OrderId = sale.Id, PrinterId = configuration["PrinterSettings:QueueName"] ?? "Printer_POS_80C",
                CreatedAt = DateTime.UtcNow, Status = "Pendiente", JobType = "Command"
            });
        }
        sale.Estado = "Cancelada"; sale.FechaCierre = DateTime.UtcNow; sale.Version++; sale.Table.Status = "Libre";
        foreach (var joined in sale.JoinedTables)
            (await context.Tables.FirstAsync(t => t.Id == joined.TableId)).Status = "Libre";
        await context.SaveChangesAsync(); await tx.CommitAsync();
        return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> MoveAsync(int company, int branch, int id, MoveTableRequest request)
    {
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable); var sale = await Editable(company, branch, id, request.Version);
        if (sale.JoinedTables.Count > 0) throw new SaleException("No se puede cambiar de mesa una cuenta con mesas unidas.", 409);
        await ValidateFreeTable(company, branch, request.TableId, id);
        sale.Table.Status = "Libre"; var target = await context.Tables.FirstAsync(t => t.Id == request.TableId); target.Status = "Ocupada"; sale.TableId = request.TableId; Changed(sale); await context.SaveChangesAsync(); await tx.CommitAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<SaleDto> JoinAsync(int company, int branch, int id, JoinTableRequest request)
    {
        await using var tx = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable); var sale = await Editable(company, branch, id, request.Version);
        if (sale.TableId == request.TableId || sale.JoinedTables.Any(j => j.TableId == request.TableId)) throw new SaleException("La mesa ya pertenece a la venta.", 409);
        var target = await context.Tables.FirstOrDefaultAsync(t => t.Id == request.TableId && t.IdEmpresa == company && t.IdSucursal == branch && t.Activo) ?? throw new SaleException("Mesa destino no encontrada.", 404);
        var other = await BaseQuery(true).FirstOrDefaultAsync(v => v.IdEmpresa == company && v.IdSucursal == branch && ActiveStates.Contains(v.Estado) && v.TableId == request.TableId);
        if (other != null && other.Id != sale.Id)
        {
            if (other.Payments.Count > 0) throw new SaleException("La mesa destino tiene pagos registrados. Completá su cobro antes de unirla.", 409);
            foreach (var item in other.Items) await AddOrMergeItem(sale, item.ProductId, item.Quantity, item.Comment);
            foreach (var command in other.Commands) command.OrderId = sale.Id;
            foreach (var payment in other.Payments) payment.OrderId = sale.Id;
            foreach (var joined in other.JoinedTables) if (!sale.JoinedTables.Any(j => j.TableId == joined.TableId)) sale.JoinedTables.Add(new SaleJoinedTable { TableId = joined.TableId });
            other.Estado = "Cancelada"; other.FechaCierre = DateTime.UtcNow; other.Version++;
        }
        sale.JoinedTables.Add(new SaleJoinedTable { TableId = request.TableId }); target.Status = "Ocupada"; Changed(sale); Recalculate(sale);
        await context.SaveChangesAsync(); await tx.CommitAsync(); return (await GetAsync(company, branch, id))!;
    }

    public async Task<object> CustomerTicketAsync(int company, int branch, int id) { var sale = await Require(company, branch, id); return Document(sale, false); }
    public async Task<object> ReceiptAsync(int company, int branch, int id) { var sale = await Require(company, branch, id); return Document(sale, true); }

    private async Task AddOrMergeItem(Order sale, int productId, decimal quantity, string? comment)
    {
        if (quantity <= 0) throw new SaleException("La cantidad debe ser mayor que cero.");
        var product = await context.Productos.AsNoTracking().FirstOrDefaultAsync(p => p.Id == productId && p.IdEmpresa == sale.IdEmpresa && p.Activo) ?? throw new SaleException("Producto no encontrado o inactivo.", 404);
        var item = sale.Items.FirstOrDefault(i => i.ProductId == productId); var now = DateTime.UtcNow;
        if (item == null) sale.Items.Add(new OrderItem { ProductId = product.Id, ProductName = product.Nombre, UnitPrice = product.PrecioConIva, Quantity = quantity, Subtotal = Money(product.PrecioConIva * quantity), Comment = CleanComment(comment), Estado = "Activo", FechaCreacion = now, FechaModificacion = now });
        else { item.Quantity += quantity; item.Comment = CleanComment(comment) ?? item.Comment; item.Subtotal = Money(item.UnitPrice * item.Quantity); item.FechaModificacion = now; }
    }

    private async Task<Order> Editable(int company, int branch, int id, long? version = null, bool allowPayments = false)
    {
        var sale = await BaseQuery(true).FirstOrDefaultAsync(v => v.Id == id && v.IdEmpresa == company && v.IdSucursal == branch) ?? throw new SaleException("Venta no encontrada.", 404);
        if (!ActiveStates.Contains(sale.Estado)) throw new SaleException("La venta ya está finalizada o cancelada.", 409);
        if (version.HasValue && version.Value != sale.Version) throw new SaleException("La venta fue modificada por otro usuario. Recargá los datos.", 409);
        if (!allowPayments && sale.Payments.Count > 0) throw new SaleException("La venta tiene pagos registrados. Completá el cobro antes de modificar el pedido o el descuento.", 409);
        return sale;
    }
    private async Task<Order> Require(int company, int branch, int id) => await BaseQuery().FirstOrDefaultAsync(v => v.Id == id && v.IdEmpresa == company && v.IdSucursal == branch) ?? throw new SaleException("Venta no encontrada.", 404);
    private IQueryable<Order> BaseQuery(bool tracking = false) { var q = context.Orders.Include(v => v.Table).ThenInclude(t => t.Sector).Include(v => v.Items).Include(v => v.Payments).Include(v => v.Commands).ThenInclude(c => c.Lines).Include(v => v.JoinedTables).AsQueryable(); return tracking ? q : q.AsNoTracking(); }
    private async Task ValidateFreeTable(int company, int branch, int tableId, int? except) { if (!await context.Tables.AnyAsync(t => t.Id == tableId && t.IdEmpresa == company && t.IdSucursal == branch && t.Activo)) throw new SaleException("Mesa no encontrada o inactiva.", 404); if (await context.Orders.AnyAsync(v => v.IdEmpresa == company && v.IdSucursal == branch && v.TableId == tableId && v.Id != except && ActiveStates.Contains(v.Estado)) || await context.SaleJoinedTables.AnyAsync(j => j.TableId == tableId && context.Orders.Any(v => v.Id == j.OrderId && ActiveStates.Contains(v.Estado)))) throw new SaleException("La mesa ya tiene una venta activa.", 409); }
    private static bool HasPendingKitchenChanges(Order sale)
    {
        var sent = sale.Commands.OrderBy(c => c.Fecha).ThenBy(c => c.Id)
            .SelectMany(c => c.Lines)
            .GroupBy(line => line.ProductId)
            .ToDictionary(group => group.Key, group => group.Last());
        return sale.Items.Any(item => !sent.TryGetValue(item.ProductId, out var line)
                || line.CurrentQuantity != item.Quantity || line.Comment != item.Comment)
            || sent.Values.Any(line => line.CurrentQuantity != 0
                && sale.Items.All(item => item.ProductId != line.ProductId));
    }

    private static void Changed(Order sale) { sale.Estado = sale.Commands.Count == 0 ? "EnPedido" : "ConCambios"; sale.Version++; }
    private static void Recalculate(Order sale) { sale.Subtotal = Money(sale.Items.Sum(i => i.Subtotal)); sale.ImporteDescuento = sale.DescuentoValor.HasValue ? DiscountAmount(sale.Subtotal, sale.DescuentoTipo!, sale.DescuentoValor.Value) : 0; sale.Total = Math.Max(0, Money(sale.Subtotal - sale.ImporteDescuento)) + sale.Payments.Sum(p => p.AdjustmentAmount); }
    private static decimal DiscountAmount(decimal subtotal, string type, decimal value) { ValidateDiscount(type, value); var amount = type == "Porcentaje" ? subtotal * value / 100 : value; if (amount > subtotal) throw new SaleException("El descuento no puede superar el subtotal."); return Money(amount); }
    private static void ValidateDiscount(string type, decimal value) { if (type is not ("Porcentaje" or "Importe")) throw new SaleException("El tipo de descuento debe ser Porcentaje o Importe."); if (value < 0 || type == "Porcentaje" && value > 100) throw new SaleException("El valor del descuento no es válido."); }
    private static string? CleanComment(string? value) { value = value?.Trim(); if (value?.Length > 500) throw new SaleException("El comentario no puede superar 500 caracteres."); return string.IsNullOrEmpty(value) ? null : value; }
    private static decimal Money(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
    private static SaleDto Map(Order v) => new() { Id = v.Id, Number = v.Numero, TableId = v.TableId, WaiterId = v.MozoId, Status = v.Estado == "ConCambios" && v.Commands.Count > 0 && !HasPendingKitchenChanges(v) ? "PedidoEnviado" : v.Estado, OpenedAt = v.FechaApertura, ClosedAt = v.FechaCierre, Subtotal = v.Subtotal, DiscountAmount = v.ImporteDescuento, PaymentAdjustment = v.Payments.Sum(p => p.AdjustmentAmount), Total = v.Total, Version = v.Version, Items = v.Items.Select(i => new SaleItemDto(i.Id, i.ProductId, i.ProductName, i.UnitPrice, i.Quantity, i.Subtotal, i.Comment, i.Estado)).ToList(), Discount = v.DescuentoValor.HasValue ? new { id = v.DescuentoId, name = v.DescuentoNombre, type = v.DescuentoTipo, value = v.DescuentoValor, amount = v.ImporteDescuento } : null, Payments = v.Payments.Select(p => (object)new { id = p.Id, paymentTypeId = p.PaymentTypeId, cardId = p.CardId, name = p.PaymentTypeName, baseAmount = p.BaseAmount ?? p.Amount, adjustmentType = p.AdjustmentType, percentage = p.Percentage, adjustmentAmount = p.AdjustmentAmount, amount = p.Amount, date = p.Fecha, reference = p.Reference }).ToList(), JoinedTableIds = v.JoinedTables.Select(j => j.TableId).ToList() };
    private static object Document(Order v, bool receipt) => new { type = receipt ? "Comprobante" : "TicketCuenta", companyId = v.IdEmpresa, saleNumber = v.Numero, date = v.FechaCierre ?? v.FechaApertura, table = v.Table.Nombre, items = v.Items.Select(i => new { quantity = i.Quantity, description = i.ProductName, unitPrice = i.UnitPrice, subtotal = i.Subtotal }), itemCount = v.Items.Sum(i => i.Quantity), v.Subtotal, discount = v.ImporteDescuento, paymentAdjustment = v.Payments.Sum(p => p.AdjustmentAmount), v.Total, payments = v.Payments.Select(p => new { name = p.PaymentTypeName, baseAmount = p.BaseAmount ?? p.Amount, adjustmentType = p.AdjustmentType, percentage = p.Percentage, adjustmentAmount = p.AdjustmentAmount, amount = p.Amount }), disclaimer = receipt ? "Documento no válido como factura" : null };
    private async Task<int> NextNumber(int company, bool command, IDbContextTransaction tx) { await using var cmd = context.Database.GetDbConnection().CreateCommand(); cmd.Transaction = tx.GetDbTransaction(); cmd.CommandText = command ? "INSERT INTO venta_contadores (id_empresa, ultimo_numero_venta, ultimo_numero_comanda) VALUES (@id,0,1) ON CONFLICT (id_empresa) DO UPDATE SET ultimo_numero_comanda=venta_contadores.ultimo_numero_comanda+1 RETURNING ultimo_numero_comanda" : "INSERT INTO venta_contadores (id_empresa, ultimo_numero_venta, ultimo_numero_comanda) VALUES (@id,1,0) ON CONFLICT (id_empresa) DO UPDATE SET ultimo_numero_venta=venta_contadores.ultimo_numero_venta+1 RETURNING ultimo_numero_venta"; var p = cmd.CreateParameter(); p.ParameterName = "id"; p.Value = company; cmd.Parameters.Add(p); return Convert.ToInt32(await cmd.ExecuteScalarAsync()); }
}
