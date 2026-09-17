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

        public async Task<PrintJob> CreatePrinterAsync(PrintJob printJob)
        {
            if (!await _context.Orders.AnyAsync(v => v.Id == printJob.OrderId))
                throw new InvalidOperationException("La venta indicada no existe.");
            printJob.Id = 0;
            printJob.CreatedAt = DateTime.UtcNow;
            printJob.Status = "Pendiente";
            printJob.JobType = "Comanda";
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
