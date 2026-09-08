using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

[Table("impresoras")]
public class PrinterConfiguration
{
    [Column("id_impresora")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("nombre")] public string Nombre { get; set; } = string.Empty;
    [Column("tipo_conexion")] public string TipoConexion { get; set; } = "Cups";
    [Column("nombre_cola")] public string? NombreCola { get; set; }
    [Column("direccion_ip")] public string? DireccionIp { get; set; }
    [Column("puerto")] public int? Puerto { get; set; }
    [Column("uso")] public string Uso { get; set; } = "Ambos";
    [Column("predeterminada")] public bool Predeterminada { get; set; }
    [Column("activa")] public bool Activa { get; set; } = true;
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("fecha_modificacion")] public DateTime FechaModificacion { get; set; }
}

public class PrinterConfigurationRequest
{
    [Required, MaxLength(150)] public string Name { get; set; } = string.Empty;
    [Required] public string ConnectionType { get; set; } = "Cups";
    [MaxLength(200)] public string? QueueName { get; set; }
    [MaxLength(45)] public string? IpAddress { get; set; }
    [Range(1, 65535)] public int? Port { get; set; }
    [Required] public string Usage { get; set; } = "Ambos";
    public bool IsDefault { get; set; }
    public bool Active { get; set; } = true;
}

public record PrinterConfigurationDto(int Id, string Name, string ConnectionType, string? QueueName, string? IpAddress, int? Port, string Usage, bool IsDefault, bool Active);
public class PrinterStatusRequest { public bool Active { get; set; } }
