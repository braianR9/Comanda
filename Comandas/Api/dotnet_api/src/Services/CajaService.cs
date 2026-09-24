using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class CajaException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class CajaService(AppDbContext context)
{
    private const string EfectivoNombre = "Efectivo";

    public async Task<CajaDto?> GetActualAsync(int company, int branch)
    {
        var caja = await Query(company).FirstOrDefaultAsync(c => c.IdSucursal == branch && c.Estado == "Abierta");
        return caja == null ? null : await MapAsync(caja);
    }

    // Usado por otros servicios (ventas) para bloquear operaciones sin caja abierta.
    public async Task RequireOpenAsync(int company, int branch)
    {
        var open = await context.Cajas.AnyAsync(c => c.IdEmpresa == company && c.IdSucursal == branch && c.Estado == "Abierta");
        if (!open) throw new CajaException("No hay una caja abierta en esta sucursal. Abrí la caja para poder vender.", 409);
    }

    public async Task<CajaDto> AbrirAsync(int company, int branch, int user, AbrirCajaRequest request)
    {
        if (request.MontoInicial < 0) throw new CajaException("El monto inicial no puede ser negativo.");
        var yaAbierta = await context.Cajas.AnyAsync(c => c.IdEmpresa == company && c.IdSucursal == branch && c.Estado == "Abierta");
        if (yaAbierta) throw new CajaException("Ya hay una caja abierta en esta sucursal. Cerrala antes de abrir una nueva.", 409);

        var caja = new Caja
        {
            IdEmpresa = company,
            IdSucursal = branch,
            Estado = "Abierta",
            UsuarioAperturaId = user,
            FechaApertura = DateTime.UtcNow,
            MontoInicial = request.MontoInicial,
            Observaciones = string.IsNullOrWhiteSpace(request.Observaciones) ? null : request.Observaciones.Trim(),
        };
        context.Cajas.Add(caja);
        try { await context.SaveChangesAsync(); }
        catch (DbUpdateException) { throw new CajaException("Ya hay una caja abierta en esta sucursal.", 409); }

        var reloaded = await Query(company).FirstAsync(c => c.Id == caja.Id);
        return await MapAsync(reloaded);
    }

    public async Task<CajaDto> CerrarAsync(int company, int branch, int user, int id, CerrarCajaRequest request)
    {
        var caja = await context.Cajas.FirstOrDefaultAsync(c => c.Id == id && c.IdEmpresa == company && c.IdSucursal == branch)
            ?? throw new CajaException("Caja no encontrada.", 404);
        if (caja.Estado != "Abierta") throw new CajaException("Esta caja ya está cerrada.", 409);

        var cierre = DateTime.UtcNow;
        var totals = await ComputeTotalsAsync(caja, cierre);

        caja.Estado = "Cerrada";
        caja.FechaCierre = cierre;
        caja.UsuarioCierreId = user;
        caja.TotalVentas = totals.TotalVentas;
        caja.TotalIngresos = totals.Ingresos;
        caja.TotalEgresos = totals.Egresos;
        caja.TotalEfectivoEsperado = totals.EfectivoEsperado;
        if (!string.IsNullOrWhiteSpace(request.Observaciones))
        {
            caja.Observaciones = string.IsNullOrWhiteSpace(caja.Observaciones)
                ? request.Observaciones.Trim()
                : $"{caja.Observaciones} | {request.Observaciones.Trim()}";
        }
        foreach (var item in totals.Detalle)
            context.CajaCierreDetalles.Add(new CajaCierreDetalle { CajaId = caja.Id, MedioPago = item.MedioPago, Total = item.Total });

        await context.SaveChangesAsync();
        var reloaded = await Query(company).FirstAsync(c => c.Id == caja.Id);
        return await MapAsync(reloaded);
    }

    public async Task<CajaMovimientoDto> AgregarMovimientoAsync(int company, int branch, int user, int cajaId, CajaMovimientoRequest request)
    {
        if (request.Monto <= 0) throw new CajaException("El monto debe ser mayor a cero.");
        if (request.Tipo != "Ingreso" && request.Tipo != "Egreso") throw new CajaException("Tipo de movimiento inválido.");
        if (string.IsNullOrWhiteSpace(request.Motivo)) throw new CajaException("Indicá un motivo para el movimiento.");

        var caja = await context.Cajas.FirstOrDefaultAsync(c => c.Id == cajaId && c.IdEmpresa == company && c.IdSucursal == branch)
            ?? throw new CajaException("Caja no encontrada.", 404);
        if (caja.Estado != "Abierta") throw new CajaException("La caja ya está cerrada.", 409);

        var movimiento = new CajaMovimiento
        {
            CajaId = caja.Id, Tipo = request.Tipo, Monto = request.Monto,
            Motivo = request.Motivo.Trim(), UsuarioId = user, Fecha = DateTime.UtcNow,
        };
        context.CajaMovimientos.Add(movimiento);
        await context.SaveChangesAsync();

        var usuario = await context.Usuarios.AsNoTracking().FirstAsync(u => u.Id == user);
        return new CajaMovimientoDto
        {
            Id = movimiento.Id, Tipo = movimiento.Tipo, Monto = movimiento.Monto, Motivo = movimiento.Motivo,
            Usuario = $"{usuario.Nombre} {usuario.Apellido}".Trim(), Fecha = movimiento.Fecha,
        };
    }

    public async Task<List<CajaDto>> HistorialAsync(int company, int branch, int take = 20)
    {
        var cajas = await Query(company).Where(c => c.IdSucursal == branch)
            .OrderByDescending(c => c.FechaApertura).Take(Math.Clamp(take, 1, 200)).ToListAsync();
        var result = new List<CajaDto>();
        foreach (var caja in cajas) result.Add(await MapAsync(caja));
        return result;
    }

    public async Task<CajaDto?> GetAsync(int company, int branch, int id)
    {
        var caja = await Query(company).FirstOrDefaultAsync(c => c.Id == id && c.IdSucursal == branch);
        return caja == null ? null : await MapAsync(caja);
    }

    private IQueryable<Caja> Query(int company) => context.Cajas.AsNoTracking().Where(c => c.IdEmpresa == company)
        .Include(c => c.UsuarioApertura).Include(c => c.UsuarioCierre);

    private async Task<(List<CajaMedioPagoDto> Detalle, decimal TotalVentas, decimal Ingresos, decimal Egresos, decimal EfectivoEsperado)> ComputeTotalsAsync(Caja caja, DateTime hasta)
    {
        var pagos = await context.SalePayments.AsNoTracking()
            .Where(p => p.Fecha >= caja.FechaApertura && p.Fecha <= hasta)
            .Join(context.Orders.Where(o => o.IdEmpresa == caja.IdEmpresa && o.IdSucursal == caja.IdSucursal), p => p.OrderId, o => o.Id, (p, o) => p)
            .GroupBy(p => p.PaymentTypeName)
            .Select(g => new CajaMedioPagoDto { MedioPago = g.Key, Total = g.Sum(p => p.Amount) })
            .ToListAsync();

        var movimientos = await context.CajaMovimientos.AsNoTracking()
            .Where(m => m.CajaId == caja.Id && m.Fecha <= hasta).ToListAsync();
        var ingresos = movimientos.Where(m => m.Tipo == "Ingreso").Sum(m => m.Monto);
        var egresos = movimientos.Where(m => m.Tipo == "Egreso").Sum(m => m.Monto);
        var efectivo = pagos.Where(p => p.MedioPago == EfectivoNombre).Sum(p => p.Total);
        var totalVentas = pagos.Sum(p => p.Total);
        var efectivoEsperado = caja.MontoInicial + efectivo + ingresos - egresos;
        return (pagos, totalVentas, ingresos, egresos, efectivoEsperado);
    }

    private async Task<CajaDto> MapAsync(Caja caja)
    {
        List<CajaMedioPagoDto> detalle;
        decimal? totalVentas, ingresos, egresos, efectivoEsperado;
        if (caja.Estado == "Abierta")
        {
            // Caja abierta: totales calculados "en vivo" con lo vendido hasta ahora.
            var totals = await ComputeTotalsAsync(caja, DateTime.UtcNow);
            detalle = totals.Detalle; totalVentas = totals.TotalVentas;
            ingresos = totals.Ingresos; egresos = totals.Egresos; efectivoEsperado = totals.EfectivoEsperado;
        }
        else
        {
            detalle = await context.CajaCierreDetalles.AsNoTracking().Where(d => d.CajaId == caja.Id)
                .OrderByDescending(d => d.Total).Select(d => new CajaMedioPagoDto { MedioPago = d.MedioPago, Total = d.Total }).ToListAsync();
            totalVentas = caja.TotalVentas; ingresos = caja.TotalIngresos;
            egresos = caja.TotalEgresos; efectivoEsperado = caja.TotalEfectivoEsperado;
        }

        var movimientos = await context.CajaMovimientos.AsNoTracking().Where(m => m.CajaId == caja.Id)
            .OrderBy(m => m.Fecha)
            .Select(m => new CajaMovimientoDto
            {
                Id = m.Id, Tipo = m.Tipo, Monto = m.Monto, Motivo = m.Motivo,
                Usuario = m.Usuario.Nombre + " " + m.Usuario.Apellido, Fecha = m.Fecha,
            }).ToListAsync();

        return new CajaDto
        {
            Id = caja.Id,
            Estado = caja.Estado,
            UsuarioApertura = $"{caja.UsuarioApertura.Nombre} {caja.UsuarioApertura.Apellido}".Trim(),
            FechaApertura = caja.FechaApertura,
            MontoInicial = caja.MontoInicial,
            UsuarioCierre = caja.UsuarioCierre == null ? null : $"{caja.UsuarioCierre.Nombre} {caja.UsuarioCierre.Apellido}".Trim(),
            FechaCierre = caja.FechaCierre,
            TotalVentas = totalVentas,
            TotalIngresos = ingresos,
            TotalEgresos = egresos,
            TotalEfectivoEsperado = efectivoEsperado,
            Observaciones = caja.Observaciones,
            Detalle = detalle,
            Movimientos = movimientos,
        };
    }
}
