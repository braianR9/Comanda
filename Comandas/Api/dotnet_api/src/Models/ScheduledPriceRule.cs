using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
namespace BarIceCreamShop.Api.Models;

[Table("reglas_precio")]
public class ScheduledPriceRule
{
    [Column("id")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_lista_precio")] public int IdListaPrecio { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = "";
    [Column("activa")] public bool Activa { get; set; } = true;
    [Column("prioridad")] public int Prioridad { get; set; }
    [Column("id_producto")] public int? IdProducto { get; set; }
    [Column("id_rubro")] public int? IdRubro { get; set; }
    [Column("id_subrubro")] public int? IdSubRubro { get; set; }
    [Column("fecha_desde")] public DateOnly FechaDesde { get; set; }
    [Column("fecha_hasta")] public DateOnly? FechaHasta { get; set; }
    [Column("dias_semana")] public int DiasSemana { get; set; } = 127;
    [Column("minuto_desde")] public int? MinutoDesde { get; set; }
    [Column("minuto_hasta")] public int? MinutoHasta { get; set; }
    [Column("operacion")] public string Operacion { get; set; } = "DisminuirPorcentaje";
    [Column("valor", TypeName = "numeric(18,2)")] public decimal Valor { get; set; }
    [Column("redondeo", TypeName = "numeric(18,2)")] public decimal Redondeo { get; set; }
    [Column("modo_redondeo")] public string ModoRedondeo { get; set; } = "Arriba";
    [Column("version"), ConcurrencyCheck] public int Version { get; set; } = 1;
    [Column("usuario")] public string Usuario { get; set; } = "";
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}

public class SaveScheduledPriceRuleRequest
{
    [Required, MaxLength(150)] public string Nombre { get; set; } = "";
    public bool Activa { get; set; } = true;
    [Range(0, 10000)] public int Prioridad { get; set; }
    public int? IdProducto { get; set; }
    public int? IdRubro { get; set; }
    public int? IdSubRubro { get; set; }
    public DateOnly FechaDesde { get; set; }
    public DateOnly? FechaHasta { get; set; }
    [Range(1, 127)] public int DiasSemana { get; set; } = 127;
    public int? MinutoDesde { get; set; }
    public int? MinutoHasta { get; set; }
    [Required] public string Operacion { get; set; } = "DisminuirPorcentaje";
    public decimal Valor { get; set; }
    public decimal Redondeo { get; set; }
    public string ModoRedondeo { get; set; } = "Arriba";
    public int Version { get; set; }
}
public class PriceQuoteRequest
{
    public int? IdListaPrecio { get; set; }
    [Required, MinLength(1), MaxLength(100)] public List<int> ProductoIds { get; set; } = [];
    // Optional instant is for simulation only. Sales always use the server clock.
    public DateTimeOffset? Fecha { get; set; }
}
public record EffectivePriceDto(int IdProducto, int IdListaPrecio, string ListaNombre, decimal? PrecioBase,
    decimal? PrecioFinal, int? IdRegla, string? ReglaNombre, DateTimeOffset FechaConsulta);
