namespace BarIceCreamShop.Api.Services;

public static class PaymentCalculation
{
    public static decimal Money(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);

    public static (decimal Base, decimal Adjustment, decimal Total) Calculate(
        decimal baseAmount, string adjustmentType, decimal percentage)
    {
        var basis = Money(baseAmount);
        if (basis <= 0) throw new SaleException("El importe base debe ser mayor que cero.");
        if (percentage < 0 || percentage > 100 ||
            adjustmentType is not ("SinAjuste" or "Recargo" or "Descuento") ||
            (adjustmentType == "SinAjuste" && percentage != 0))
            throw new SaleException("El ajuste del medio de pago no es válido.");
        var adjustment = Money(basis * percentage / 100) * (adjustmentType == "Descuento" ? -1 : 1);
        return (basis, adjustment, basis + adjustment);
    }
}
