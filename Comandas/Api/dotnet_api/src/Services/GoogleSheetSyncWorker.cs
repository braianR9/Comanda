using BarIceCreamShop.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class GoogleSheetSyncWorker(
    IServiceScopeFactory scopeFactory,
    GoogleSheetsService sheets,
    ILogger<GoogleSheetSyncWorker> logger) : BackgroundService
{
    private const int MaxAttempts = 5;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var processed = sheets.Enabled && await ProcessNextAsync(stoppingToken);
                if (!processed)
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
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

    private async Task<bool> ProcessNextAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var reports = scope.ServiceProvider.GetRequiredService<ReportsService>();

        var job = await db.GoogleSheetJobs
            .Where(x => x.Status == "Pendiente")
            .OrderBy(x => x.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
        if (job is null) return false;

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
                return true;
            }

            var rows = await reports.SaleLinesAsync(order.IdEmpresa, order.IdSucursal, order.Id);
            await sheets.AppendSaleRowsAsync(branch.GoogleSheetId, rows, cancellationToken);

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
            // No reintentar en el mismo instante: deja que la pausa del bucle actúe como backoff.
            return false;
        }

        return true;
    }
}
