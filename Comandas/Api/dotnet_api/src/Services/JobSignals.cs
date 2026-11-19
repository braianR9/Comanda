using System.Data.Common;
using System.Runtime.CompilerServices;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace BarIceCreamShop.Api.Services;

/// Aviso en memoria de que hay trabajo nuevo. Los workers y el agente de impresión esperan este
/// aviso en lugar de consultar la base cada pocos segundos: así la base (Neon) puede apagarse
/// cuando nadie usa el sistema y no se paga cómputo ocioso.
public sealed class WorkSignal
{
    private readonly object _lock = new();
    private long _version;
    private TaskCompletionSource _changed = new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// Cambia con cada aviso. Se lee ANTES de consultar la base, para no perder un aviso que llegue en el medio.
    public long Version { get { lock (_lock) return _version; } }

    public void Notify()
    {
        TaskCompletionSource previous;
        lock (_lock)
        {
            _version++;
            previous = _changed;
            _changed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        previous.TrySetResult();
    }

    /// Espera un aviso posterior a <paramref name="seen"/>. Devuelve false si pasó el tiempo sin avisos.
    public async Task<bool> WaitAsync(long seen, TimeSpan timeout, CancellationToken cancellationToken)
    {
        Task changed;
        lock (_lock)
        {
            if (_version != seen) return true;
            changed = _changed.Task;
        }
        try
        {
            await changed.WaitAsync(timeout, cancellationToken);
            return true;
        }
        catch (TimeoutException)
        {
            return false;
        }
    }
}

/// Revisión de resguardo alineada a la hora en punto (UTC). Todos los workers y agentes revisan la
/// cola en el mismo momento, así la base se despierta una sola vez por hora sin importar cuántas
/// computadoras con agente queden prendidas.
public static class HourlyCheck
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    /// Número de franja horaria: cambia en cada hora en punto.
    public static long Slot(DateTime utc) => utc.Ticks / Interval.Ticks;

    /// Tiempo hasta la próxima hora en punto (con un segundo de margen).
    public static TimeSpan UntilNext(DateTime utc) =>
        TimeSpan.FromTicks((Slot(utc) + 1) * Interval.Ticks - utc.Ticks) + TimeSpan.FromSeconds(1);
}

public sealed class JobSignals
{
    /// Trabajos de impresión nuevos o que vuelven a quedar pendientes (reimpresiones).
    public WorkSignal Print { get; } = new();

    /// Ventas para sincronizar con Google Sheets.
    public WorkSignal Sheets { get; } = new();
}

/// Detecta, al guardar, trabajos de impresión o de Google Sheets que quedaron pendientes y avisa
/// cuando ya están en la base: enseguida, o al confirmar la transacción si se guardaron dentro de una.
public sealed class JobSignalInterceptor(JobSignals signals) : SaveChangesInterceptor, IDbTransactionInterceptor
{
    private sealed class Pending { public bool Print; public bool Sheets; }
    private readonly ConditionalWeakTable<DbContext, Pending> _pending = new();

    private void Collect(DbContext? context)
    {
        if (context == null) return;
        var print = context.ChangeTracker.Entries<PrintJob>().Any(e => e.State == EntityState.Added
            || (e.State == EntityState.Modified && e.Entity.Status == "Pendiente" && e.Property(x => x.Status).IsModified))
            // Cambios de impresoras o computadoras pueden destrabar trabajos que esperaban una impresora.
            || context.ChangeTracker.Entries<PrinterConfiguration>().Any(e => e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            || context.ChangeTracker.Entries<PrintAgent>().Any(e => e.State is EntityState.Added or EntityState.Deleted);
        var sheets = context.ChangeTracker.Entries<GoogleSheetJob>().Any(e => e.State == EntityState.Added
            || (e.State == EntityState.Modified && e.Entity.Status == "Pendiente" && e.Property(x => x.Status).IsModified));
        if (!print && !sheets) return;
        var pending = _pending.GetOrCreateValue(context);
        pending.Print |= print;
        pending.Sheets |= sheets;
    }

    private void Flush(DbContext? context, bool committed)
    {
        if (context == null || !_pending.TryGetValue(context, out var pending)) return;
        // Dentro de una transacción el aviso espera al commit; si no, el worker no vería el trabajo.
        if (committed && context.Database.CurrentTransaction != null) return;
        _pending.Remove(context);
        if (!committed) return;
        if (pending.Print) signals.Print.Notify();
        if (pending.Sheets) signals.Sheets.Notify();
    }

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        Collect(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
        InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        Collect(eventData.Context);
        return ValueTask.FromResult(result);
    }

    public override int SavedChanges(SaveChangesCompletedEventData eventData, int result)
    {
        Flush(eventData.Context, committed: true);
        return result;
    }

    public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result,
        CancellationToken cancellationToken = default)
    {
        Flush(eventData.Context, committed: true);
        return ValueTask.FromResult(result);
    }

    public override void SaveChangesFailed(DbContextErrorEventData eventData)
    {
        // Si el guardado falló fuera de una transacción, no hay nada que avisar.
        if (eventData.Context?.Database.CurrentTransaction == null) Flush(eventData.Context, committed: false);
    }

    public override Task SaveChangesFailedAsync(DbContextErrorEventData eventData, CancellationToken cancellationToken = default)
    {
        SaveChangesFailed(eventData);
        return Task.CompletedTask;
    }

    // ─── Transacciones ───────────────────────────────────────────────────────
    public void TransactionCommitted(DbTransaction transaction, TransactionEndEventData eventData) => Committed(eventData.Context);

    public Task TransactionCommittedAsync(DbTransaction transaction, TransactionEndEventData eventData,
        CancellationToken cancellationToken = default)
    {
        Committed(eventData.Context);
        return Task.CompletedTask;
    }

    public void TransactionRolledBack(DbTransaction transaction, TransactionEndEventData eventData) => Flush(eventData.Context, committed: false);

    public Task TransactionRolledBackAsync(DbTransaction transaction, TransactionEndEventData eventData,
        CancellationToken cancellationToken = default)
    {
        Flush(eventData.Context, committed: false);
        return Task.CompletedTask;
    }

    private void Committed(DbContext? context)
    {
        if (context == null || !_pending.TryGetValue(context, out var pending)) return;
        _pending.Remove(context);
        if (pending.Print) signals.Print.Notify();
        if (pending.Sheets) signals.Sheets.Notify();
    }
}
