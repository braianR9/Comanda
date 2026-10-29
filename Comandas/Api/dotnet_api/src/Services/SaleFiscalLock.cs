using BarIceCreamShop.Api.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace BarIceCreamShop.Api.Services;

// Se comparte con la anulación para impedir que aparezca una factura mientras se anula.
public sealed class SaleFiscalLock : IAsyncDisposable
{
    private readonly NpgsqlConnection connection;
    private SaleFiscalLock(NpgsqlConnection connection) => this.connection = connection;
    public static async Task<SaleFiscalLock> AcquireAsync(AppDbContext db, int saleId)
    {
        var connection = new NpgsqlConnection(db.Database.GetConnectionString());
        try
        {
            await connection.OpenAsync();
            await connection.BeginTransactionAsync();
            await using var command = new NpgsqlCommand("SELECT pg_advisory_xact_lock(73422, @id)", connection);
            command.Parameters.AddWithValue("id", saleId);
            await command.ExecuteNonQueryAsync();
            return new(connection);
        }
        catch { await connection.DisposeAsync(); throw; }
    }
    public ValueTask DisposeAsync() => connection.DisposeAsync();
}
