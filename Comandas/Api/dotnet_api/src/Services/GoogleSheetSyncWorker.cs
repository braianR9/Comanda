using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class GoogleSheetSyncWorker(
    IServiceScopeFactory scopeFactory,
    GoogleSheetsService sheets,
    JobSignals signals,
    ILogger<GoogleSheetSyncWorker> logger) : BackgroundService
{
    private const int MaxAttempts = 5;

    // Sin trabajos, espera el aviso de una venta nueva; igual revisa la cola a cada hora en punto
    // (HourlyCheck). No consulta la base cada pocos segundos, así puede apagarse cuando no hay uso.
    private static readonly TimeSpan RetryDelay = TimeSpan.FromMinutes(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Se lee antes de consultar: un aviso que llegue mientras tanto no se pierde.
                var seen = signals.Sheets.Version;
                var result = sheets.Enabled ? await ProcessNextAsync(stoppingToken) : JobResult.Empty;
                if (result == JobResult.Failed)
                    await Task.Delay(RetryDelay, stoppingToken);
                else if (result == JobResult.Empty)
                    await signals.Sheets.WaitAsync(seen, HourlyCheck.UntilNext(DateTime.UtcNow), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error al procesar la cola de sincronización con Google Sheets.");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private enum JobResult { Processed, Empty, Failed }

    private async Task<JobResult> ProcessNextAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var reports = scope.ServiceProvider.GetRequiredService<ReportsService>();

        var job = await db.GoogleSheetJobs
            .Where(x => x.Status == "Pendiente")
            .OrderBy(x => x.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
        if (job is null) return JobResult.Empty;

        try
        {
            var order = await db.Orders.AsNoTracking()
                .SingleAsync(o => o.Id == job.OrderId, cancellationToken);
            var branch = await db.Sucursales.AsNoTracking()
                .SingleAsync(s => s.Id == job.BranchId, cancellationToken);
            if (string.IsNullOrWhiteSpace(branch.GoogleSheetId))
            {
                // Se desactivó la planilla para esta sucursal después de encolar el trabajo.
                job.Status = "Cancelado";
                await db.SaveChangesAsync(cancellationToken);
                return JobResult.Processed;
            }

            if (await db.SaleVoids.AnyAsync(v => v.OrderId == order.Id, cancellationToken))
            {
                // Venta anulada que ya estaba en la planilla: se borran sus filas.
                var printedNumber = (await db.Orders.AsNoTracking().Include(o => o.Commands)
                    .SingleAsync(o => o.Id == order.Id, cancellationToken)).PrintedNumber;
                var items = await (from item in db.Set<OrderItem>().AsNoTracking()
                    join product in db.Productos.AsNoTracking() on item.ProductId equals product.Id
                    where item.OrderId == order.Id && item.Estado == "Activo"
                    select new { item.ProductName, product.Nombre }).ToListAsync(cancellationToken);
                var names = items.SelectMany(x => new[] { x.ProductName.Trim(), x.Nombre.Trim() }).ToHashSet();
                var deleted = await sheets.DeleteSaleRowsAsync(branch.GoogleSheetId, printedNumber, names, items.Count, cancellationToken);
                logger.LogInformation("Venta {OrderId} anulada: {Deleted} filas borradas de Google Sheets.", order.Id, deleted);
            }
            else
            {
                var rows = await reports.SaleLinesAsync(order.IdEmpresa, order.IdSucursal, order.Id);
                await sheets.AppendSaleRowsAsync(branch.GoogleSheetId, rows, cancellationToken);
            }

            job.Status = "Enviado";
            await db.SaveChangesAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            job.Attempts++;
            job.Error = ex.Message;
            job.Status = job.Attempts >= MaxAttempts ? "Error" : "Pendiente";
            await db.SaveChangesAsync(cancellationToken);
            logger.LogError(ex, "No se pudo sincronizar la venta {OrderId} con Google Sheets (intento {Attempt}).",
                job.OrderId, job.Attempts);
            // No reintentar en el mismo instante: el bucle espera un minuto antes de volver a probar.
            return JobResult.Failed;
        }

        return JobResult.Processed;
    }
}
