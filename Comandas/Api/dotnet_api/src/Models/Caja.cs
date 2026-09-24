using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("cajas")]
public class Caja
{
    [Column("id_caja")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("estado")] public string Estado { get; set; } = "Abierta";
    [Column("id_usuario_apertura")] public int UsuarioAperturaId { get; set; }
    [Column("fecha_apertura")] public DateTime FechaApertura { get; set; }
    [Column("monto_inicial", TypeName = "decimal(18,2)")] public decimal MontoInicial { get; set; }
    [Column("id_usuario_cierre")] public int? UsuarioCierreId { get; set; }
    [Column("fecha_cierre")] public DateTime? FechaCierre { get; set; }
    [Column("total_ventas", TypeName = "decimal(18,2)")] public decimal? TotalVentas { get; set; }
    [Column("total_ingresos", TypeName = "decimal(18,2)")] public decimal? TotalIngresos { get; set; }
    [Column("total_egresos", TypeName = "decimal(18,2)")] public decimal? TotalEgresos { get; set; }
    [Column("total_efectivo_esperado", TypeName = "decimal(18,2)")] public decimal? TotalEfectivoEsperado { get; set; }
    [Column("observaciones")] public string? Observaciones { get; set; }

    public Usuario UsuarioApertura { get; set; } = null!;
    public Usuario? UsuarioCierre { get; set; }
}

[Table("caja_movimientos")]
public class CajaMovimiento
{
    [Column("id_movimiento")] public int Id { get; set; }
    [Column("id_caja")] public int CajaId { get; set; }
    [Column("tipo")] public string Tipo { get; set; } = "Ingreso";
    [Column("monto", TypeName = "decimal(18,2)")] public decimal Monto { get; set; }
    [Column("motivo")] public string Motivo { get; set; } = string.Empty;
    [Column("id_usuario")] public int UsuarioId { get; set; }
    [Column("fecha")] public DateTime Fecha { get; set; }

    public Usuario Usuario { get; set; } = null!;
}

[Table("caja_cierre_detalle")]
public class CajaCierreDetalle
{
    [Column("id_caja")] public int CajaId { get; set; }
    [Column("medio_pago")] public string MedioPago { get; set; } = string.Empty;
    [Column("total", TypeName = "decimal(18,2)")] public decimal Total { get; set; }
}
