using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("sectores")]
public class Sector
{
    [Column("id_sector")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string Descripcion { get; set; } = string.Empty;
    [Column("orden")] public int Orden { get; set; }
    [Column("activo")] public bool Activo { get; set; } = true;
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}

public class SectorRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = string.Empty;
    [Required, MaxLength(1000)] public string Description { get; set; } = string.Empty;
    [Range(0, int.MaxValue)] public int Order { get; set; }
}

public class SectorStatusRequest { public bool Active { get; set; } }
public class SectorOrderItem { [Range(1, int.MaxValue)] public int Id { get; set; } [Range(0, int.MaxValue)] public int Order { get; set; } }
public class ReorderSectorsRequest { [Required, MinLength(1)] public List<SectorOrderItem> Items { get; set; } = []; }

public class SectorDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public int Order { get; set; }
    public bool Active { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
