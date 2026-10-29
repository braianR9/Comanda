using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("sistemas_eventos")]
public class SystemEvent
{
    [Column("id")] public long Id { get; set; }
    [Column("fecha")] public DateTime Date { get; set; } = DateTime.UtcNow;
    [Column("tipo")] public string Type { get; set; } = "Error";
    [Column("nivel")] public string Level { get; set; } = "Error";
    [Column("origen")] public string Source { get; set; } = "API";
    [Column("mensaje")] public string Message { get; set; } = "";
    [Column("detalle")] public string? Detail { get; set; }
    [Column("id_empresa")] public int? CompanyId { get; set; }
    [Column("id_sucursal")] public int? BranchId { get; set; }
    [Column("id_usuario")] public int? UserId { get; set; }
    [Column("metodo")] public string? Method { get; set; }
    [Column("ruta")] public string? Path { get; set; }
    [Column("estado_http")] public int? StatusCode { get; set; }
    [Column("referencia")] public string? TraceId { get; set; }
    [Column("resuelto")] public bool Resolved { get; set; }
    [Column("nota")] public string? Note { get; set; }
}

public record SystemPage<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize);
public class SystemCompanyRequest
{
    [Required, MaxLength(150)] public string Nombre { get; set; } = "";
    [MaxLength(30)] public string? Cuit { get; set; }
    [MaxLength(150)] public string? Email { get; set; }
    [MaxLength(50)] public string? Telefono { get; set; }
    public bool Activa { get; set; } = true;
}
public class SystemBranchRequest
{
    [Required, MaxLength(150)] public string Nombre { get; set; } = "";
    [MaxLength(300)] public string? Direccion { get; set; }
    [MaxLength(50)] public string? Telefono { get; set; }
    public bool Activa { get; set; } = true;
}
public class SystemUserRequest : UsuarioRequest
{
    [Range(1, int.MaxValue)] public int IdSucursal { get; set; }
}
public record SystemEventResolution(bool Resolved, [MaxLength(2000)] string? Note);
public record SystemPasswordRequest([Required] string CurrentPassword, [Required, MinLength(12), MaxLength(72)] string NewPassword);
