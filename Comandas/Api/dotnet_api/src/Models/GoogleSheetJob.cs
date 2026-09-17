using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    [Table("google_sheet_jobs")]
    public class GoogleSheetJob
    {
        [Column("id_google_sheet_job")]
        public int Id { get; set; }

        [Column("id_venta")]
        public int OrderId { get; set; }

        [Column("id_sucursal")]
        public int BranchId { get; set; }

        [Column("estado")]
        public string Status { get; set; } = "Pendiente";

        [Column("intentos")]
        public int Attempts { get; set; }

        [Column("error")]
        public string? Error { get; set; }

        [Column("fecha_creacion")]
        public DateTime CreatedAt { get; set; }
    }

    public class GoogleSheetSettingsRequest
    {
        /// Acepta el ID solo o el link completo de la planilla; se normaliza al guardar.
        public string? SheetIdOrUrl { get; set; }
    }
}
