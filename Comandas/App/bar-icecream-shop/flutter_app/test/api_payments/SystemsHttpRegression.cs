using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading.RateLimiting;
using BarIceCreamShop.Api.Controllers;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Middleware;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Security;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;

static class SystemsHttpRegression
{
    public static async Task Run(AppDbContext db, IConfiguration config, Usuario user)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [], EnvironmentName = "Regression" });
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddSingleton<IConfiguration>(config).AddSingleton(db);
        builder.Services.AddScoped<UsuarioService>().AddScoped<SystemAdminService>().AddScoped<AuthService>();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddSingleton<SystemEventSink>();
        builder.Services.AddControllers(o => o.Filters.Add<SystemErrorResultFilter>()).AddApplicationPart(typeof(SystemAdminController).Assembly).AddNewtonsoftJson();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o => {
            o.TokenValidationParameters = new() { ValidIssuer = config["Jwt:Issuer"], ValidAudience = config["Jwt:Audience"],
                IssuerSigningKey = new SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(config["Jwt:Key"]!)) };
            o.Events = new() { OnTokenValidated = SystemsOwner.ValidateSession };
        });
        builder.Services.AddAuthorization(o => o.AddPolicy(SystemsOwner.Policy, p => p.RequireAssertion(c => SystemsOwner.IsOwner(c.User, config))));
        builder.Services.AddRateLimiter(o => {
            o.RejectionStatusCode = 429;
            foreach (var name in new[] { "systems-login", "client-errors" }) o.AddPolicy(name, c => RateLimitPartition.GetFixedWindowLimiter("test", _ => new FixedWindowRateLimiterOptions {
                PermitLimit = 10, Window = TimeSpan.FromMinutes(5), QueueLimit = 0
            }));
        });
        await using var app = builder.Build();
        app.UseMiddleware<SystemErrorMiddleware>(); app.UseMiddleware<ApiKeyMiddleware>();
        app.UseAuthentication(); app.UseAuthorization(); app.UseRateLimiter();
        app.MapControllers();
        app.MapGet("/api/tenant-probe", () => "Tenant access").RequireAuthorization();
        app.MapGet("/api/error-probe", (Func<string>)(() => throw new InvalidOperationException("password=do-not-store"))).RequireAuthorization();
        await app.StartAsync();
        try
        {
            using var http = new HttpClient { BaseAddress = new Uri(app.Services.GetRequiredService<IServer>()
                .Features.Get<IServerAddressesFeature>()!.Addresses.Single()) };
            http.DefaultRequestHeaders.Add("focoKey", config["ApiKey:Value"]);
            Check((await http.GetAsync("/api/system/companies")).StatusCode == HttpStatusCode.Unauthorized, "Anonymous requests cannot enter systems API");
            foreach (var name in new[] { "ADMIN", "CAJA", "EMPLEADO" })
            {
                var role = await db.Roles.FirstOrDefaultAsync(r => r.Nombre == name || (name == "CAJA" && r.Nombre == "ENCARGADO"));
                if (role == null) throw new Exception("Missing regression role: " + name);
                user.IdRol = role.Id; await db.SaveChangesAsync();
                var login = await app.Services.GetRequiredService<AuthService>().LoginAsync(new() { Email = user.Email, Password = "different-test-password" });
                http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login!.Token);
                Check((await http.GetAsync("/api/system/companies")).StatusCode == HttpStatusCode.Forbidden, name + " receives HTTP 403 on systems endpoints");
            }
            var diagnostics = await http.PostAsJsonAsync("/api/diagnostics/client-error", new { message = "A client regression error", stack = "regression", library = "test" });
            Check(diagnostics.StatusCode == HttpStatusCode.OK, "Tenant application can report errors with authenticated context");
            Check((await http.GetAsync("/api/error-probe")).StatusCode == HttpStatusCode.InternalServerError, "Unexpected API errors are handled centrally");
            var sink = app.Services.GetRequiredService<SystemEventSink>();
            var captured = new List<SystemEvent>(); while (sink.Queue.Reader.TryRead(out var item)) captured.Add(item);
            Check(captured.Any(e => e.Source == "Flutter" && e.CompanyId == user.IdEmpresa && e.BranchId == user.IdSucursal && e.UserId == user.Id), "Client error records carry company, branch and user");
            Check(captured.Any(e => e.StatusCode == 500 && !(e.Detail ?? "").Contains("do-not-store")), "Unhandled errors retain diagnostics with sensitive values hidden");
            http.DefaultRequestHeaders.Authorization = null;
            var rejected = await http.PostAsJsonAsync("/api/system/login", new { email = "wrong@example.test", password = "private-test-password" });
            Check(rejected.StatusCode == HttpStatusCode.Unauthorized, "Owner login rejects another email");
            var ownerLogin = await http.PostAsJsonAsync("/api/system/login", new { email = config["SystemsOwner:Email"], password = "private-test-password" });
            Check(ownerLogin.StatusCode == HttpStatusCode.OK, "Configured owner can sign in through the actual API");
            using var result = JsonDocument.Parse(await ownerLogin.Content.ReadAsStringAsync());
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result.RootElement.GetProperty("data").GetProperty("token").GetString());
            Check((await http.GetAsync("/api/system/companies")).StatusCode == HttpStatusCode.OK, "Owner can read global companies through the protected API");
            var created = await http.PostAsJsonAsync("/api/system/companies", new { nombre = "HTTP regression company", email = "", activa = false });
            Check(created.StatusCode == HttpStatusCode.OK, "Company contact email is optional through actual model validation");
            Check((await http.GetAsync("/api/tenant-probe")).StatusCode == HttpStatusCode.Unauthorized, "Owner identity remains separate from operational tenant sessions");
            config["SystemsOwner:PasswordHash"] = BCrypt.Net.BCrypt.HashPassword("http-rotated-password");
            Check((await http.GetAsync("/api/system/session")).StatusCode == HttpStatusCode.Unauthorized, "Changing owner credentials revokes an active HTTP session");
        }
        finally { await app.StopAsync(); }
    }
    static void Check(bool ok, string message) { if (!ok) throw new Exception(message); Console.WriteLine("PASS: " + message); }
}
