using System.IdentityModel.Tokens.Jwt;
using System.Reflection;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using BarIceCreamShop.Api.Controllers;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;

static class SystemsAdminRegression
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    public static async Task Run()
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
            ["Jwt:Key"] = new string('r', 48), ["Jwt:Issuer"] = "regression", ["Jwt:Audience"] = "regression",
            ["Jwt:DurationInMinutes"] = "30", ["SystemsOwner:Email"] = "owner@example.test",
            ["SystemsOwner:PasswordHash"] = BCrypt.Net.BCrypt.HashPassword("private-test-password"),
            ["ApiKey:Value"] = "private-test-api-key"
        }).Build();
        var token = SystemsOwner.CreateToken(config);
        var principal = new JwtSecurityTokenHandler().ValidateToken(token, new TokenValidationParameters {
            ValidateIssuer = true, ValidIssuer = "regression", ValidateAudience = true, ValidAudience = "regression",
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!)), ValidateLifetime = true,
        }, out _);
        Check(SystemsOwner.IsOwner(principal, config), "Only the configured owner has global access");
        foreach (var role in new[] { "ADMIN", "CAJA", "ENCARGADO", "EMPLEADO", "SYSTEMS" })
            Check(!SystemsOwner.IsOwner(new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("rol_nombre", role), new Claim(ClaimTypes.Email, "owner@example.test")], "test")), config),
                role + " cannot become systems owner, even with the owner's email");
        config["SystemsOwner:PasswordHash"] = BCrypt.Net.BCrypt.HashPassword("rotated-test-password");
        Check(!SystemsOwner.IsOwner(principal, config), "Changing the owner's password revokes existing owner tokens");
        config["SystemsOwner:PasswordHash"] = BCrypt.Net.BCrypt.HashPassword("private-test-password");
        Check(typeof(SystemAdminController).GetCustomAttributes<AuthorizeAttribute>().Any(a => a.Policy == SystemsOwner.Policy), "Systems endpoints require the owner policy");

        var cs = TestConfig.ConnectionString();
        if (new Npgsql.NpgsqlConnectionStringBuilder(cs).Host is not ("localhost" or "127.0.0.1" or "::1")) throw new Exception("Only the local database may be tested.");
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(cs).Options);
        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            // El esquema y todas las filas de prueba se revierten con la transacción.
            using var reader = new StreamReader(typeof(SystemsOwner).Assembly.GetManifestResourceStream("BarIceCreamShop.Api.SystemsSchema.sql")!);
            var sql = (await reader.ReadToEndAsync()).Replace("BEGIN;", "").Replace("COMMIT;", "")
                .Replace("CREATE TABLE IF NOT EXISTS sistemas_eventos", "CREATE TEMP TABLE sistemas_eventos");
            await db.Database.ExecuteSqlRawAsync(sql);
            var users = new UsuarioService(db); var service = new SystemAdminService(db, users);
            var controller = new SystemAdminController(db, service, users, config);
            var company = await service.SaveCompany(null, new() { Nombre = "Systems Regression " + Guid.NewGuid() });
            var other = await service.SaveCompany(null, new() { Nombre = "Systems Regression other " + Guid.NewGuid() });
            var branch = await service.SaveBranch(company.Id, null, new() { Nombre = "Principal" });
            var foreign = await service.SaveBranch(other.Id, null, new() { Nombre = "Ajena" });
            var roleId = await db.Roles.Where(r => r.Nombre == "EMPLEADO").Select(r => r.Id).FirstAsync();
            var request = new SystemUserRequest { Nombre = "Systems", Apellido = "Regression", Email = Guid.NewGuid() + "@example.test", Password = "private-test-password", IdRol = roleId, IdSucursal = branch.Id };
            var created = await service.SaveUser(company.Id, null, request);
            Check(created.IdSucursal == branch.Id && created.SucursalNombre == "Principal", "Owner can create a user in a chosen company and branch");
            request.IdSucursal = foreign.Id;
            await Reject(() => service.SaveUser(company.Id, created.Id, request), "User cannot be assigned to another company's branch");
            await Reject(() => service.SaveBranch(company.Id, foreign.Id, new() { Nombre = "Invalid" }), "A branch cannot be edited through the wrong company");
            request.IdSucursal = branch.Id;

            var auth = new AuthService(db, config);
            var session = await auth.LoginAsync(new() { Email = request.Email, Password = request.Password! });
            Check(session != null, "Active tenant user can sign in");
            var userPrincipal = new JwtSecurityTokenHandler().ValidateToken(session!.Token, new TokenValidationParameters {
                ValidIssuer = "regression", ValidAudience = "regression",
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!))
            }, out _);
            Check(await Valid(userPrincipal), "An active tenant session is valid");
            var entity = await db.Usuarios.SingleAsync(u => u.Id == created.Id);
            entity.Activo = false; await db.SaveChangesAsync();
            Check(!await Valid(userPrincipal) && await auth.LoginAsync(new() { Email = request.Email, Password = request.Password! }) == null,
                "Disabling user blocks login and already issued sessions");
            entity.Activo = true; branch.Activa = false; await db.SaveChangesAsync();
            Check(!await Valid(userPrincipal) && await auth.LoginAsync(new() { Email = request.Email, Password = request.Password! }) == null,
                "Disabling branch blocks login and already issued sessions");
            branch.Activa = true; company.Activa = false; await db.SaveChangesAsync();
            Check(!await Valid(userPrincipal) && await auth.LoginAsync(new() { Email = request.Email, Password = request.Password! }) == null,
                "Disabling company blocks login and already issued sessions");
            company.Activa = true; entity.PasswordHash = BCrypt.Net.BCrypt.HashPassword("different-test-password"); await db.SaveChangesAsync();
            Check(!await Valid(userPrincipal), "Resetting a user's password revokes their existing session");
            Check(!await Valid(principal, "/api/usuarios"), "Owner token cannot access tenant operational endpoints");

            var sector = new Sector { IdEmpresa = company.Id, Nombre = "Prueba", FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow };
            db.Sectors.Add(sector); await db.SaveChangesAsync();
            var table = new Table { IdEmpresa = company.Id, IdSucursal = branch.Id, SectorId = sector.Id, Nombre = "Prueba", Capacidad = 2,
                FechaCreacion = DateTime.UtcNow, FechaModificacion = DateTime.UtcNow };
            db.Tables.Add(table); await db.SaveChangesAsync();
            var start = new DateTimeOffset(2026, 5, 20, 3, 0, 0, TimeSpan.Zero);
            var sale = new Order { IdEmpresa = company.Id, IdSucursal = branch.Id, TableId = table.Id, UsuarioId = entity.Id,
                Numero = 1, Estado = "Finalizada", FechaApertura = start.UtcDateTime.AddHours(-5), FechaCierre = start.UtcDateTime.AddHours(12), Total = 150, Subtotal = 150,
                Payments = [new() { Amount = 60, Fecha = start.UtcDateTime.AddHours(12), PaymentTypeName = "Efectivo", UsuarioId = entity.Id },
                    new() { Amount = 90, Fecha = start.UtcDateTime.AddDays(1), PaymentTypeName = "Tarjeta", UsuarioId = entity.Id }] };
            db.Orders.Add(sale); await db.SaveChangesAsync();
            var sales = Data(await controller.Transactions(start, start.AddDays(1), company.Id, null, null));
            Check(sales.GetProperty("total").GetInt32() == 1 && sales.GetProperty("amount").GetDecimal() == 150,
                "Sales date filter uses closing time and counts a split-payment sale once");
            var payments = Data(await controller.Transactions(start, start.AddDays(1), company.Id, branch.Id, null, "payments"));
            Check(payments.GetProperty("total").GetInt32() == 1 && payments.GetProperty("amount").GetDecimal() == 60,
                "Payment filter uses payment date with an exclusive next-day boundary");
            Check(payments.GetProperty("daily")[0].GetProperty("date").GetDateTime().Day == 20,
                "Daily totals use the requested local timezone");
            Check(Data(await controller.Transactions(start, start.AddDays(1), other.Id, null, null)).GetProperty("total").GetInt32() == 0,
                "Company filters do not mix transactions");
            await Reject(() => controller.Transactions(start, start.AddDays(367), null, null, null), "Oversized date ranges are rejected");
            Check(Data(await controller.Transaction(sale.Id)).GetProperty("payments").GetArrayLength() == 2, "Transaction detail includes actual payments");
            var eventRow = new SystemEvent { Message = "Regression failure", CompanyId = company.Id, Date = start.UtcDateTime };
            db.SystemEvents.Add(eventRow); await db.SaveChangesAsync();
            var errorPage = Data(await controller.Events(start, start.AddDays(1), company: company.Id));
            Check(errorPage.GetProperty("total").GetInt32() == 1, "Error history supports date and company filters");
            await controller.Resolve(eventRow.Id, new(true, "Corregido en regresión"));
            Check(Data(await controller.Events(start, start.AddDays(1), company: company.Id, resolved: false)).GetProperty("total").GetInt32() == 0,
                "Resolved errors leave the pending view and retain their history");
            Check(await db.SystemEvents.AnyAsync(e => e.Type == "Audit" && e.CompanyId == company.Id), "Owner's management changes leave an audit trail");
            var sink = new SystemEventSink(config, new HttpContextAccessor());
            sink.Error("Regression", "password=do-not-store " + config["ApiKey:Value"] + " Bearer " + token);
            sink.Queue.Reader.TryRead(out var sanitized);
            Check(sanitized != null && !sanitized.Message.Contains("do-not-store") && !sanitized.Message.Contains(config["ApiKey:Value"]!) && !sanitized.Message.Contains(token),
                "Error logging removes passwords, API keys and bearer tokens");
            await SystemsHttpRegression.Run(db, config, entity);

            async Task<bool> Valid(ClaimsPrincipal candidate, string path = "/api/system/session")
            {
                var services = new ServiceCollection().AddSingleton<IConfiguration>(config).AddSingleton(db).BuildServiceProvider();
                await using (services)
                {
                    var http = new DefaultHttpContext { RequestServices = services }; http.Request.Path = path;
                    var validation = new TokenValidatedContext(http, new AuthenticationScheme("Bearer", null, typeof(JwtBearerHandler)), new JwtBearerOptions()) { Principal = candidate };
                    await SystemsOwner.ValidateSession(validation);
                    return validation.Result?.Failure == null;
                }
            }
        }
        finally { await tx.RollbackAsync(); }
        Console.WriteLine("Systems checks passed. Every test company, user, transaction and event was rolled back.");
    }
    static JsonElement Data(object response) => JsonSerializer.SerializeToElement(((ApiResponse<object>)response).Data, Json);
    static void Check(bool ok, string message) { if (!ok) throw new Exception(message); Console.WriteLine("PASS: " + message); }
    static async Task Reject(Func<Task> action, string message) { try { await action(); } catch (SaleException) { Check(true, message); return; } throw new Exception("Expected rejection: " + message); }
}
