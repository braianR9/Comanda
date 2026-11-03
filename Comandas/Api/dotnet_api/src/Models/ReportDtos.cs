namespace BarIceCreamShop.Api.Models;

public class SalesDetailFilter
{
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
    public bool UseTimeRange { get; set; }
    public TimeSpan? TimeFrom { get; set; }
    public TimeSpan? TimeTo { get; set; }
    public int? RubroId { get; set; }
    public int? SubRubroId { get; set; }
    public int? SectorId { get; set; }
    public int? OrderNumber { get; set; }

    /// Id interno de la venta (no el impreso); usado por la sincronización con Google Sheets.
    public int? SaleId { get; set; }
}

public record SalesDetailLineDto(
    DateTime Date,
    int OrderNumber,
    int ProductCode,
    string ProductName,
    decimal Quantity,
    decimal Total,

    /// Total prorrateado según el descuento y el ajuste (recargo/descuento) del
    /// medio de pago realmente cobrados en la venta; es lo que el cliente pagó.
    decimal RealAmount,
    string RubroNombre,
    string? SubRubroNombre,
    string TipoPedido,
    string? SectorNombre);

public record SalesDetailResultDto(
    List<SalesDetailLineDto> Items,
    decimal TotalQuantity,
    decimal TotalAmount,
    decimal TotalRealAmount);

/// Renglón del Libro de IVA Ventas. Las notas de crédito van con importes negativos.
public record VatSalesLineDto(
    DateTime Date,
    string Voucher,
    int PointOfSale,
    string Customer,
    string VatCondition,
    string? Cuit,
    decimal Subtotal,
    decimal Vat105,
    decimal Vat21,
    decimal Vat27,
    decimal Total,
    bool Testing);

public record VatSalesTotalsDto(decimal Subtotal, decimal Vat105, decimal Vat21, decimal Vat27, decimal Total);

public record VatSalesResultDto(List<VatSalesLineDto> Items, VatSalesTotalsDto Totals);
