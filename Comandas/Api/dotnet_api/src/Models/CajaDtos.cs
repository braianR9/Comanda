namespace BarIceCreamShop.Api.Models;

public record AbrirCajaRequest(decimal MontoInicial, string? Observaciones);
public record CerrarCajaRequest(string? Observaciones);
public record CajaMovimientoRequest(string Tipo, decimal Monto, string Motivo);

public class CajaMedioPagoDto
{
    public string MedioPago { get; set; } = string.Empty;
    public decimal Total { get; set; }
}

public class CajaMovimientoDto
{
    public int Id { get; set; }
    public string Tipo { get; set; } = string.Empty;
    public decimal Monto { get; set; }
    public string Motivo { get; set; } = string.Empty;
    public string Usuario { get; set; } = string.Empty;
    public DateTime Fecha { get; set; }
}

public class CajaDto
{
    public int Id { get; set; }
    public string Estado { get; set; } = string.Empty;
    public string UsuarioApertura { get; set; } = string.Empty;
    public DateTime FechaApertura { get; set; }
    public decimal MontoInicial { get; set; }
    public string? UsuarioCierre { get; set; }
    public DateTime? FechaCierre { get; set; }
    public decimal? TotalVentas { get; set; }
    public decimal? TotalIngresos { get; set; }
    public decimal? TotalEgresos { get; set; }
    public decimal? TotalEfectivoEsperado { get; set; }
    public string? Observaciones { get; set; }
    public List<CajaMedioPagoDto> Detalle { get; set; } = [];
    public List<CajaMovimientoDto> Movimientos { get; set; } = [];
}
