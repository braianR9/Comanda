using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using ClosedXML.Excel;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class ReportsService(AppDbContext db)
{
    // Fijo en vez de TimeZoneInfo.Local: el servidor puede estar configurado en
    // UTC (lo habitual en hosting), y ahí ToLocalTime() no corrige nada y el
    // filtro de "hora exacta" termina comparando contra la hora equivocada.
    private static readonly TimeSpan ArgentinaOffset = TimeSpan.FromHours(-3);

    private record Row(
        DateTime Date, int OrderId, int ProductCode, string ProductName,
        decimal Quantity, decimal Total, int RubroId, string RubroNombre,
        int? SubRubroId, string? SubRubroNombre, int SectorId, string SectorNombre);

    private record OrderTotals(int PrintedNumber, decimal Subtotal, decimal Total);

    public async Task<SalesDetailResultDto> SalesDetailAsync(int company, int branch, SalesDetailFilter filter)
    {
        var (items, totalQuantity, totalAmount, totalRealAmount) = await BuildAsync(company, branch, filter);
        return new SalesDetailResultDto(items, totalQuantity, totalAmount, totalRealAmount);
    }

    /// Líneas de una venta puntual, usadas al sincronizar con Google Sheets.
    public async Task<List<SalesDetailLineDto>> SaleLinesAsync(int company, int branch, int saleId)
    {
        var (items, _, _, _) = await BuildAsync(company, branch, new SalesDetailFilter { SaleId = saleId });
        return items;
    }

    public async Task<byte[]> ExportSalesDetailXlsxAsync(int company, int branch, SalesDetailFilter filter)
    {
        var (items, totalQuantity, totalAmount, totalRealAmount) = await BuildAsync(company, branch, filter);

        using var workbook = new XLWorkbook();
        var sheet = workbook.Worksheets.Add("Listado de ventas");
        string[] headers = ["Fecha", "N° de pedido", "Código", "Nombre", "Cantidad", "Total", "Total real", "Rubro", "Subrubro", "Tipo de pedido", "Sector"];
        for (var col = 0; col < headers.Length; col++) sheet.Cell(1, col + 1).Value = headers[col];
        sheet.Row(1).Style.Font.Bold = true;

        var row = 2;
        foreach (var item in items)
        {
            sheet.Cell(row, 1).Value = item.Date;
            sheet.Cell(row, 1).Style.DateFormat.Format = "dd/MM/yyyy HH:mm";
            sheet.Cell(row, 2).Value = item.OrderNumber;
            sheet.Cell(row, 3).Value = item.ProductCode;
            sheet.Cell(row, 4).Value = item.ProductName;
            sheet.Cell(row, 5).Value = item.Quantity;
            sheet.Cell(row, 6).Value = item.Total;
            sheet.Cell(row, 7).Value = item.RealAmount;
            sheet.Cell(row, 8).Value = item.RubroNombre;
            sheet.Cell(row, 9).Value = item.SubRubroNombre ?? "";
            sheet.Cell(row, 10).Value = item.TipoPedido;
            sheet.Cell(row, 11).Value = item.SectorNombre ?? "";
            row++;
        }
        sheet.Cell(row, 4).Value = "Totales";
        sheet.Cell(row, 4).Style.Font.Bold = true;
        sheet.Cell(row, 5).Value = totalQuantity;
        sheet.Cell(row, 5).Style.Font.Bold = true;
        sheet.Cell(row, 6).Value = totalAmount;
        sheet.Cell(row, 6).Style.Font.Bold = true;
        sheet.Cell(row, 7).Value = totalRealAmount;
        sheet.Cell(row, 7).Style.Font.Bold = true;
        sheet.Columns().AdjustToContents();

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return stream.ToArray();
    }

    private async Task<(List<SalesDetailLineDto> Items, decimal TotalQuantity, decimal TotalAmount, decimal TotalRealAmount)> BuildAsync(
        int company, int branch, SalesDetailFilter filter)
    {
        var query =
            from item in db.Set<OrderItem>().AsNoTracking()
            join sale in db.Orders.AsNoTracking() on item.OrderId equals sale.Id
            join table in db.Tables.AsNoTracking() on sale.TableId equals table.Id
            join sector in db.Sectors.AsNoTracking() on table.SectorId equals sector.Id
            join product in db.Productos.AsNoTracking() on item.ProductId equals product.Id
            join rubro in db.Rubros.AsNoTracking() on product.IdRubro equals rubro.Id
            join subRubro in db.SubRubros.AsNoTracking() on product.IdSubRubro equals subRubro.Id into subRubros
            from subRubro in subRubros.DefaultIfEmpty()
            where sale.IdEmpresa == company && sale.IdSucursal == branch
                  && sale.Estado == "Finalizada" && item.Estado == "Activo"
            select new { item, product, rubro, subRubro, sector };

        if (filter.From.HasValue) query = query.Where(x => x.item.FechaCreacion >= AsUtc(filter.From.Value));
        if (filter.To.HasValue) query = query.Where(x => x.item.FechaCreacion <= AsUtc(filter.To.Value));
        if (filter.RubroId.HasValue) query = query.Where(x => x.rubro.Id == filter.RubroId);
        if (filter.SubRubroId.HasValue) query = query.Where(x => x.subRubro != null && x.subRubro.Id == filter.SubRubroId);
        if (filter.SectorId.HasValue) query = query.Where(x => x.sector.Id == filter.SectorId);
        if (filter.SaleId.HasValue) query = query.Where(x => x.item.OrderId == filter.SaleId);

        // Tope defensivo: evita traer un rango de fechas descomunal a memoria.
        var rows = await query.OrderBy(x => x.item.FechaCreacion).Take(20000)
            .Select(x => new Row(x.item.FechaCreacion, x.item.OrderId, x.product.Codigo, x.product.Nombre,
                x.item.Quantity, x.item.Subtotal, x.rubro.Id, x.rubro.Nombre,
                x.subRubro == null ? (int?)null : x.subRubro.Id, x.subRubro == null ? null : x.subRubro.Nombre,
                x.sector.Id, x.sector.Nombre))
            .ToListAsync();

        // El "N° de pedido" impreso en comandas/tickets sale de la primera comanda
        // de la venta, no del correlativo interno de venta (ver Order.PrintedNumber).
        // Subtotal/Total de la venta sirven para prorratear el descuento y el ajuste
        // (recargo/descuento) del medio de pago en cada línea: Total ya los incluye.
        var orderIds = rows.Select(x => x.OrderId).Distinct().ToList();
        var orderTotals = orderIds.Count == 0
            ? new Dictionary<int, OrderTotals>()
            : await db.Orders.AsNoTracking().Include(o => o.Commands)
                .Where(o => orderIds.Contains(o.Id))
                .ToDictionaryAsync(o => o.Id, o => new OrderTotals(o.PrintedNumber, o.Subtotal, o.Total));

        IEnumerable<Row> filtered = rows;
        if (filter.OrderNumber.HasValue)
            filtered = filtered.Where(x => orderTotals.GetValueOrDefault(x.OrderId)?.PrintedNumber == filter.OrderNumber.Value);
        if (filter.UseTimeRange && filter.TimeFrom.HasValue && filter.TimeTo.HasValue)
        {
            var from = filter.TimeFrom.Value;
            var to = filter.TimeTo.Value;
            filtered = filtered.Where(x =>
            {
                var timeOfDay = DateTime.SpecifyKind(x.Date, DateTimeKind.Utc).Add(ArgentinaOffset).TimeOfDay;
                return from <= to
                    ? timeOfDay >= from && timeOfDay <= to
                    : timeOfDay >= from || timeOfDay <= to;
            });
        }

        var list = filtered.ToList();
        // Hoy toda venta pasa por una mesa/sector: no existe todavía una venta de "Mostrador".
        var items = list.Select(x =>
        {
            var totals = orderTotals.GetValueOrDefault(x.OrderId);
            var ratio = totals != null && totals.Subtotal > 0 ? totals.Total / totals.Subtotal : 1m;
            var realAmount = Math.Round(x.Total * ratio, 2);
            return new SalesDetailLineDto(
                ToArgentinaTime(x.Date), totals?.PrintedNumber ?? 0, x.ProductCode, x.ProductName,
                x.Quantity, x.Total, realAmount, x.RubroNombre, x.SubRubroNombre, "Salón", x.SectorNombre);
        }).ToList();

        return (items, list.Sum(x => x.Quantity), list.Sum(x => x.Total), items.Sum(x => x.RealAmount));
    }

    private static readonly JsonSerializerOptions VatJson = new(JsonSerializerDefaults.Web);

    /// Libro de IVA Ventas: comprobantes autorizados de la sucursal, por fecha de autorización.
    public async Task<VatSalesResultDto> VatSalesAsync(int company, int branch, SalesDetailFilter filter)
    {
        var query = db.Invoices.AsNoTracking()
            .Where(x => x.CompanyId == company && x.BranchId == branch && x.Status == "Autorizado");
        if (filter.From.HasValue)
        {
            var from = AsUtc(filter.From.Value);
            query = query.Where(x => (x.AuthorizedAt ?? x.CreatedAt) >= from);
        }
        if (filter.To.HasValue)
        {
            var to = AsUtc(filter.To.Value);
            query = query.Where(x => (x.AuthorizedAt ?? x.CreatedAt) <= to);
        }
        var invoices = await query
            .OrderBy(x => x.AuthorizedAt ?? x.CreatedAt).ThenBy(x => x.PointOfSale).ThenBy(x => x.Number)
            .Take(20000).ToListAsync();

        var items = invoices
            .Where(x => !filter.UseTimeRange || !filter.TimeFrom.HasValue || !filter.TimeTo.HasValue
                || InTimeRange(x.AuthorizedAt ?? x.CreatedAt, filter.TimeFrom.Value, filter.TimeTo.Value))
            .Select(x =>
            {
                var sign = x.IsCreditNote ? -1m : 1m;
                var vat = JsonSerializer.Deserialize<List<InvoiceVat>>(x.VatJson, VatJson) ?? [];
                decimal VatAt(decimal rate) => sign * vat.Where(v => v.Rate == rate).Sum(v => v.Amount);
                var hasCuit = x.DocType is AfipCodes.DocCuit or AfipCodes.DocCuil && x.DocNumber > 0;
                return new VatSalesLineDto(
                    ToArgentinaTime(x.AuthorizedAt ?? x.CreatedAt), $"{AfipCodes.TypeName(x.Type)} N° {x.Number}",
                    x.PointOfSale, string.IsNullOrWhiteSpace(x.ReceiverName) ? "Consumidor final" : x.ReceiverName,
                    VatConditionName(x.ReceiverVatCondition), hasCuit ? x.DocNumber.ToString() : null,
                    sign * x.Net, VatAt(10.5m), VatAt(21m), VatAt(27m), sign * x.Total, x.Environment != "Produccion");
            })
            .ToList();

        return new VatSalesResultDto(items, new VatSalesTotalsDto(
            items.Sum(x => x.Subtotal), items.Sum(x => x.Vat105), items.Sum(x => x.Vat21),
            items.Sum(x => x.Vat27), items.Sum(x => x.Total)));
    }

    public async Task<byte[]> ExportVatSalesXlsxAsync(int company, int branch, SalesDetailFilter filter)
    {
        var result = await VatSalesAsync(company, branch, filter);

        using var workbook = new XLWorkbook();
        var sheet = workbook.Worksheets.Add("Libro IVA Ventas");
        string[] headers = ["Fecha", "Comprobante", "Punto de venta", "Cliente", "Condición IVA", "CUIT", "Subtotal", "IVA 10,5 %", "IVA 21%", "IVA 27%", "Total"];
        for (var col = 0; col < headers.Length; col++) sheet.Cell(1, col + 1).Value = headers[col];
        sheet.Row(1).Style.Font.Bold = true;

        var row = 2;
        foreach (var item in result.Items)
        {
            sheet.Cell(row, 1).Value = item.Date;
            sheet.Cell(row, 1).Style.DateFormat.Format = "dd/MM/yyyy HH:mm";
            sheet.Cell(row, 2).Value = item.Testing ? $"{item.Voucher} (prueba)" : item.Voucher;
            sheet.Cell(row, 3).Value = item.PointOfSale;
            sheet.Cell(row, 4).Value = item.Customer;
            sheet.Cell(row, 5).Value = item.VatCondition;
            sheet.Cell(row, 6).Value = item.Cuit ?? "";
            sheet.Cell(row, 7).Value = item.Subtotal;
            sheet.Cell(row, 8).Value = item.Vat105;
            sheet.Cell(row, 9).Value = item.Vat21;
            sheet.Cell(row, 10).Value = item.Vat27;
            sheet.Cell(row, 11).Value = item.Total;
            row++;
        }
        sheet.Cell(row, 6).Value = "Totales";
        sheet.Cell(row, 7).Value = result.Totals.Subtotal;
        sheet.Cell(row, 8).Value = result.Totals.Vat105;
        sheet.Cell(row, 9).Value = result.Totals.Vat21;
        sheet.Cell(row, 10).Value = result.Totals.Vat27;
        sheet.Cell(row, 11).Value = result.Totals.Total;
        sheet.Row(row).Style.Font.Bold = true;
        sheet.Range(2, 7, row, 11).Style.NumberFormat.Format = "#,##0.00";
        sheet.Columns().AdjustToContents();

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return stream.ToArray();
    }

    private static bool InTimeRange(DateTime utc, TimeSpan from, TimeSpan to)
    {
        var timeOfDay = ToArgentinaTime(utc).TimeOfDay;
        return from <= to ? timeOfDay >= from && timeOfDay <= to : timeOfDay >= from || timeOfDay <= to;
    }

    private static string VatConditionName(int code) => code switch
    {
        AfipCodes.CondResponsableInscripto => "Responsable inscripto",
        AfipCodes.CondExento => "Exento",
        AfipCodes.CondConsumidorFinal => "Consumidor final",
        AfipCodes.CondMonotributo => "Monotributo",
        _ => "No categorizado",
    };

    private static DateTime AsUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc)
    };

    private static DateTime ToArgentinaTime(DateTime value) =>
        DateTime.SpecifyKind(value, DateTimeKind.Utc).Add(ArgentinaOffset);
}
