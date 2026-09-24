using Microsoft.EntityFrameworkCore;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;

namespace BarIceCreamShop.Api.Services
{
    public class PrinterService
    {
        private readonly AppDbContext _context;

        public PrinterService(AppDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<PrintJob>> GetAllPrintersAsync()
            => await _context.PrintJobs.ToListAsync();

        public async Task<PrintJob?> GetPrintJobByIdAsync(int id)
            => await _context.PrintJobs.FindAsync(id);

        private static readonly HashSet<string> ValidJobTypes = ["TicketVenta", "CierreCaja"];

        public async Task<PrintJob> CreatePrinterAsync(PrintJob printJob)
        {
            if (printJob.OrderId is null && printJob.CajaId is null)
                throw new InvalidOperationException("Indicá una venta o una caja para imprimir.");
            if (printJob.OrderId is not null && !await _context.Orders.AnyAsync(v => v.Id == printJob.OrderId))
                throw new InvalidOperationException("La venta indicada no existe.");
            if (printJob.CajaId is not null && !await _context.Cajas.AnyAsync(c => c.Id == printJob.CajaId))
                throw new InvalidOperationException("La caja indicada no existe.");
            printJob.Id = 0;
            printJob.CreatedAt = DateTime.UtcNow;
            printJob.Status = "Pendiente";
            // Cualquier otro valor recibido (p.ej. "Command" del cliente legado) se normaliza a "Comanda".
            printJob.JobType = ValidJobTypes.Contains(printJob.JobType) ? printJob.JobType : "Comanda";
            _context.PrintJobs.Add(printJob);
            await _context.SaveChangesAsync();
            return printJob;
        }

        public async Task<bool> DeletePrinterAsync(int id)
        {
            var printJob = await _context.PrintJobs.FindAsync(id);
            if (printJob == null) return false;
            _context.PrintJobs.Remove(printJob);
            await _context.SaveChangesAsync();
            return true;
        }
    }
}
