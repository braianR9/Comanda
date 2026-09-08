using System.ComponentModel.DataAnnotations;

namespace BarIceCreamShop.Api.Models;

public record ReferenciaDto(int Id, string Nombre);
public record AlicuotaReferenciaDto(int Id, string Nombre, string Descripcion, decimal Porcentaje);

public class ProductListDto
{
    public int Id { get; set; }
    public int Codigo { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string TipoProducto { get; set; } = string.Empty;
    public ReferenciaDto Rubro { get; set; } = null!;
    public ReferenciaDto? SubRubro { get; set; }
    public decimal PrecioConIva { get; set; }
    public string? ImagenUrl { get; set; }
    public bool Activo { get; set; }
}

public class ProductDetailDto : ProductListDto
{
    public string? Descripcion { get; set; }
    public AlicuotaReferenciaDto Alicuota { get; set; } = null!;
    public decimal CostoSinIva { get; set; }
    public decimal CostoConIva { get; set; }
    public decimal PrecioSinIva { get; set; }
    public decimal RentabilidadPorcentaje { get; set; }
    public bool MostrarDelivery { get; set; }
    public bool MostrarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
    public bool SolicitarCantidad { get; set; }
    public bool SolicitarPrecioUnitario { get; set; }
    public bool SolicitarPrecioYCalcularCantidad { get; set; }
    public string? Preparacion { get; set; }
    public int Orden { get; set; }
    public DateTime FechaCreacion { get; set; }
    public DateTime FechaModificacion { get; set; }
    public ProductStockDto? Stock { get; set; }
}

public class CreateProductRequest
{
    [Required, MaxLength(200)] public string Nombre { get; set; } = string.Empty;
    [MaxLength(2000)] public string? Descripcion { get; set; }
    [Required, MaxLength(50)] public string TipoProducto { get; set; } = "ProductoSimple";
    [Range(1, int.MaxValue)] public int IdRubro { get; set; }
    public int? IdSubRubro { get; set; }
    [Range(1, int.MaxValue)] public int IdAlicuota { get; set; }
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal CostoConIva { get; set; }
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal PrecioConIva { get; set; }
    public bool MostrarDelivery { get; set; }
    public bool MostrarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
    public bool SolicitarCantidad { get; set; }
    public bool SolicitarPrecioUnitario { get; set; }
    public bool SolicitarPrecioYCalcularCantidad { get; set; }
    [MaxLength(4000)] public string? Preparacion { get; set; }
    public int Orden { get; set; }
    public ProductStockRequest? Stock { get; set; }
}

public class UpdateProductRequest : CreateProductRequest { }
public class UpdateProductStatusRequest { public bool Activo { get; set; } }
public class UploadProductImageRequest { [Required] public IFormFile Imagen { get; set; } = null!; }

public class ProductStockRequest
{
    [Required, MaxLength(20)] public string OperacionCantidad { get; set; } = "Entero";
    [Range(typeof(decimal), "0", "999999999999999.999")] public decimal StockActual { get; set; }
    [Range(typeof(decimal), "0", "999999999999999.999")] public decimal StockMinimo { get; set; }
    [Range(typeof(decimal), "0", "999999999999999.999")] public decimal StockIdeal { get; set; }
    public bool TieneAlarmaStock { get; set; }
    public bool TieneAlarmaStockMinimo { get; set; }
    public bool ComprobarStockAlVender { get; set; }
    [Required, MaxLength(20)] public string ActualizarSobre { get; set; } = "Producto";
}

public class ProductStockDto : ProductStockRequest
{
    public int Id { get; set; }
    public int IdProducto { get; set; }
    public int IdSucursal { get; set; }
    public DateTime FechaModificacion { get; set; }
}

public class PagedResult<T>
{
    public IReadOnlyList<T> Items { get; set; } = [];
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalItems { get; set; }
    public int TotalPages { get; set; }
}
