using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("mesas")]
public class Table
{
    [Column("id_mesa")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("id_sector")] public int SectorId { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("descripcion")] public string? Descripcion { get; set; }
    [Column("forma")] public string Forma { get; set; } = "Rectangular";
    [Column("capacidad")] public int Capacidad { get; set; }
    [Column("posicion_x", TypeName = "decimal(8,6)")] public decimal PositionX { get; set; }
    [Column("posicion_y", TypeName = "decimal(8,6)")] public decimal PositionY { get; set; }
    [Column("numero")] public int Number { get; set; }
    [Column("estado")] public string Status { get; set; } = "Libre";
    [Column("activo")] public bool Activo { get; set; } = true;
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
    public Sector Sector { get; set; } = null!;
}

public class TableRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = string.Empty;
    [MaxLength(1000)] public string? Description { get; set; }
    [Range(1, int.MaxValue)] public int SectorId { get; set; }
    [MaxLength(30)] public string Shape { get; set; } = "Rectangular";
    [MaxLength(30)] public string? Type { get; set; }
    [Range(1, int.MaxValue)] public int Capacity { get; set; }
    [Range(typeof(decimal), "0", "1")] public decimal PositionX { get; set; }
    [Range(typeof(decimal), "0", "1")] public decimal PositionY { get; set; }
}

public class TableStatusRequest { public bool Active { get; set; } }

public class TableDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int SectorId { get; set; }
    public SectorDto Sector { get; set; } = null!;
    public string Shape { get; set; } = string.Empty;
    public string Type => Shape;
    public int Capacity { get; set; }
    public decimal PositionX { get; set; }
    public decimal PositionY { get; set; }
    public string Status { get; set; } = string.Empty;
    public bool Active { get; set; }
}
