using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public static class PrintJobQueue
{
    /// Una comanda sale por todas las impresoras activas de la sucursal con uso Comanda o Ambos:
    /// se encola un trabajo por impresora. Sin impresoras configuradas queda el trabajo genérico
    /// (cola por defecto). Devuelve los trabajos agregados al contexto, sin guardar.
    public static async Task<List<PrintJob>> AddComandaAsync(AppDbContext db, PrintJob template, int company, int branch)
    {
        var printers = await db.PrinterConfigurations.AsNoTracking()
            .Where(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Activa && (x.Uso == "Comanda" || x.Uso == "Ambos"))
            .OrderBy(x => x.Id)
            .Select(x => new { x.Id, Queue = x.NombreCola ?? x.Nombre })
            .ToListAsync();

        var jobs = printers.Count == 0
            ? [template]
            : printers.Select(p => new PrintJob
            {
                OrderId = template.OrderId, CajaId = template.CajaId, UserId = template.UserId, Reprint = template.Reprint,
                CreatedAt = template.CreatedAt, Status = template.Status, JobType = "Comanda",
                PrinterConfigurationId = p.Id, PrinterId = p.Queue
            }).ToList();
        db.PrintJobs.AddRange(jobs);
        return jobs;
    }
}
