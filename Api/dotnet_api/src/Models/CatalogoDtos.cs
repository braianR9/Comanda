using System.ComponentModel.DataAnnotations;

namespace BarIceCreamShop.Api.Models;

public class CatalogStatusRequest { public bool Activo { get; set; } }

public class RubroRequest
{
    [Required, MaxLength(200)] public string Nombre { get; set; } = string.Empty;
    [MaxLength(2000)] public string? Descripcion { get; set; }
    [Required, MaxLength(50)] public string TipoObservacion { get; set; } = "SinObservaciones";
    public bool AplicarProductos { get; set; } = true;
    public bool AplicarDelivery { get; set; }
    public bool AplicarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
}

public class RubroDto
{
    public int Id { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string? Descripcion { get; set; }
    public string TipoObservacion { get; set; } = string.Empty;
    public string? ImagenUrl { get; set; }
    public bool AplicarProductos { get; set; }
    public bool AplicarDelivery { get; set; }
    public bool AplicarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
    public bool Activo { get; set; }
    public IReadOnlyList<SubRubroDto>? SubRubros { get; set; }
}

public class UploadRubroImageRequest { [Required] public IFormFile Imagen { get; set; } = null!; }

public class SubRubroRequest
{
    [Required, MaxLength(200)] public string Nombre { get; set; } = string.Empty;
    [MaxLength(2000)] public string? Descripcion { get; set; }
    [Required, MaxLength(50)] public string TipoObservacion { get; set; } = "SinObservaciones";
    public bool AplicarProductos { get; set; } = true;
    public bool AplicarIngredientes { get; set; }
    public bool AplicarDelivery { get; set; }
    public bool AplicarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
}

public class UpdateSubRubroRequest : SubRubroRequest
{
    [Range(1, int.MaxValue)] public int IdRubro { get; set; }
}

public class SubRubroDto
{
    public int Id { get; set; }
    public int IdRubro { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string? Descripcion { get; set; }
    public string TipoObservacion { get; set; } = string.Empty;
    public string? ImagenUrl { get; set; }
    public bool AplicarProductos { get; set; }
    public bool AplicarIngredientes { get; set; }
    public bool AplicarDelivery { get; set; }
    public bool AplicarSalon { get; set; }
    public bool MostrarCartaDigital { get; set; }
    public bool Activo { get; set; }
}

public class UploadSubRubroImageRequest { [Required] public IFormFile Imagen { get; set; } = null!; }

public class AlicuotaRequest
{
    [Required, MaxLength(100)] public string Nombre { get; set; } = string.Empty;
    [Required, MaxLength(500)] public string Descripcion { get; set; } = string.Empty;
    [Range(typeof(decimal), "0", "100")] public decimal Porcentaje { get; set; }
}

public class AlicuotaDto
{
    public int Id { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string Descripcion { get; set; } = string.Empty;
    public decimal Porcentaje { get; set; }
    public bool Activa { get; set; }
    public bool Global { get; set; }
    // Alias requeridos por el modelo ProductTax actual de Flutter.
    public string Name => Nombre;
    public string Description => Descripcion;
    public decimal Percentage => Porcentaje;
}
