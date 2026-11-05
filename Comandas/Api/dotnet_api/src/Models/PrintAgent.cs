using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models;

/// Agente de impresión de una sucursal. Se identifica con una clave; se guarda solo su hash.
[Table("agentes_impresion")]
public class PrintAgent
{
    [Column("id_agente_impresion")] public int Id { get; set; }
    [Column("id_empresa")] public int IdEmpresa { get; set; }
    [Column("id_sucursal")] public int IdSucursal { get; set; }
    [Column("clave_hash")] public string ClaveHash { get; set; } = string.Empty;
    [Column("fecha_creacion")] public DateTime FechaCreacion { get; set; }
    [Column("ultimo_contacto")] public DateTime? UltimoContacto { get; set; }
    [Column("equipo")] public string? Equipo { get; set; }
}

public record PrintAgentStatusDto(bool Configured, DateTime? CreatedAt, DateTime? LastSeen, string? Machine);
public record PrintAgentKeyDto(string Key);
public record PrintAgentPrinterDto(string Name, string ConnectionType, string? QueueName, string? IpAddress, int? Port);
public record PrintAgentJobDto(int Id, string Type, PrintAgentPrinterDto Printer, string Content);
public class PrintAgentResultRequest { public bool Ok { get; set; } public string? Error { get; set; } }
