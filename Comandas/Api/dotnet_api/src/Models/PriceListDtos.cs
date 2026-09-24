using System.ComponentModel.DataAnnotations;

namespace BarIceCreamShop.Api.Models;

public record PriceListDto(
    int Id, string Nombre, bool EsPredeterminada, bool Activa,
    DateTime FechaCreacion, DateTime FechaModificacion, int CantidadPrecios);

public class CreatePriceListRequest
{
    [Required, MaxLength(150)] public string Nombre { get; set; } = string.Empty;
    /// Si se indica, copia todos los precios actuales de esa lista a la nueva.
    public int? CopiarDesdeListaId { get; set; }
}

public class UpdatePriceListRequest
{
    [Required, MaxLength(150)] public string Nombre { get; set; } = string.Empty;
}

public class PriceListStatusRequest { public bool Activa { get; set; } }

public record ProductPriceDto(
    int IdProducto, int Codigo, string Nombre,
    ReferenciaDto Rubro, ReferenciaDto? SubRubro, decimal? Precio);

public class SetProductPriceRequest
{
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal Precio { get; set; }
}

public class BulkPriceFilter
{
    public int? IdRubro { get; set; }
    public int? IdSubRubro { get; set; }
    public string? Texto { get; set; }
    public List<int>? ProductoIds { get; set; }
}

public class BulkPriceOperationRequest
{
    public BulkPriceFilter Filtro { get; set; } = new();
    /// AumentarPorcentaje | DisminuirPorcentaje | AumentarImporte | DisminuirImporte
    [Required] public string Operacion { get; set; } = string.Empty;
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal Valor { get; set; }
}

public record BulkPricePreviewItem(int IdProducto, string Nombre, decimal? PrecioActual, decimal PrecioNuevo);

public class SetSucursalPriceListRequest
{
    /// null = la sucursal usa la lista predeterminada de la empresa.
    public int? IdListaPrecio { get; set; }
}
