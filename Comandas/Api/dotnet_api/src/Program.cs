using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Middleware;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Configuration
    .SetBasePath(Path.Combine(Directory.GetCurrentDirectory(), "src"))
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    // Secretos de cada instalación (no versionado). Ver appsettings.Local.example.json.
    .AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

// ─── Secretos obligatorios ──────────────────────────────────────────────────
var missingSecrets = new List<string>();
if (string.IsNullOrWhiteSpace(builder.Configuration.GetConnectionString("DefaultConnection")))
    missingSecrets.Add("ConnectionStrings:DefaultConnection");
if (string.IsNullOrWhiteSpace(builder.Configuration["ApiKey:Value"]))
    missingSecrets.Add("ApiKey:Value");
if ((builder.Configuration["Jwt:Key"] ?? string.Empty).Length < 32)
    missingSecrets.Add("Jwt:Key (mínimo 32 caracteres)");
if (missingSecrets.Count > 0)
    throw new InvalidOperationException(
        "Falta configurar: " + string.Join(", ", missingSecrets) +
        ". Copiá src/appsettings.Local.example.json a src/appsettings.Local.json y completalo, " +
        "o usá variables de entorno (ej. Jwt__Key).");

if (string.IsNullOrWhiteSpace(builder.Configuration["urls"]))
{
    builder.WebHost.UseUrls("http://localhost:5001");
}

// ─── Base de datos PostgreSQL ────────────────────────────────────────────────
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        npgsql => npgsql.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)));

// ─── Servicios de la aplicación ─────────────────────────────────────────────
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<OrderService>();
builder.Services.AddScoped<TableService>();
builder.Services.AddScoped<PrinterService>();
builder.Services.AddScoped<PrinterConfigurationService>();
builder.Services.AddSingleton<PrinterTransport>();
// En la nube Workers:PrintJobs=false: imprime el agente local del comercio, que lee la misma cola.
if (builder.Configuration.GetValue("Workers:PrintJobs", true))
    builder.Services.AddHostedService<PrintJobWorker>();
builder.Services.AddScoped<SectorService>();
builder.Services.AddScoped<ProductoService>();
builder.Services.AddScoped<CatalogosService>();
builder.Services.AddScoped<StockMovementService>();
builder.Services.AddScoped<CustomerService>();
builder.Services.AddScoped<UsuarioService>();
builder.Services.AddScoped<ReportsService>();
builder.Services.AddScoped<CajaService>();
builder.Services.AddScoped<PurchaseService>();
builder.Services.AddScoped<CompanySettingsService>();
builder.Services.AddScoped<PriceListService>();
builder.Services.AddScoped<PosService>();
builder.Services.AddHttpClient<AfipClient>(client => client.Timeout = TimeSpan.FromSeconds(30));
builder.Services.AddScoped<AfipCredentialService>();
builder.Services.AddScoped<InvoiceService>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<GoogleSheetsService>();
if (builder.Configuration.GetValue("Workers:GoogleSheets", true))
    builder.Services.AddHostedService<GoogleSheetSyncWorker>();

// ─── Controllers ────────────────────────────────────────────────────────────
builder.Services.AddControllers()
    .AddNewtonsoftJson();

// ─── CORS para Flutter Web (desarrollo + orígenes extra en Cors:Origins) ───
var corsOrigins = new[] { "http://localhost:3000", "http://127.0.0.1:3000" }
    .Concat((builder.Configuration["Cors:Origins"] ?? string.Empty)
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
    .ToArray();
builder.Services.AddCors(options =>
{
    options.AddPolicy("FlutterDevCors", policy =>
    {
        policy
            .WithOrigins(corsOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var jwt = builder.Configuration.GetSection("Jwt");
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwt["Issuer"],
            ValidAudience = jwt["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!))
        };
    });
builder.Services.AddAuthorization();

// ─── Swagger ────────────────────────────────────────────────────────────────
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Bar & Ice Cream Shop API",
        Version = "v1",
        Description = "API para gestión de comandas del bar/heladería."
    });

    // Definición del esquema de API Key en Swagger
    options.AddSecurityDefinition("ApiKey", new OpenApiSecurityScheme
    {
        Name = builder.Configuration["ApiKey:HeaderName"] ?? "focoKey",
        Type = SecuritySchemeType.ApiKey,
        Scheme = "ApiKeyScheme",
        In = ParameterLocation.Header,
        Description = "Ingresá la API Key configurada en ApiKey:Value."
    });

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization", Type = SecuritySchemeType.Http,
        Scheme = "bearer", BearerFormat = "JWT", In = ParameterLocation.Header
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "ApiKey"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

var webRootPath = app.Environment.WebRootPath
    ?? Path.Combine(app.Environment.ContentRootPath, "wwwroot");
Directory.CreateDirectory(Path.Combine(webRootPath, "uploads", "empresas"));
Directory.CreateDirectory(Path.Combine(webRootPath, "uploads", "productos"));
Directory.CreateDirectory(Path.Combine(webRootPath, "uploads", "rubros"));
Directory.CreateDirectory(Path.Combine(webRootPath, "uploads", "subrubros"));

// ─── Swagger UI ─────────────────────────────────────────────────────────────
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Bar & Ice Cream Shop API v1");
    c.RoutePrefix = "swagger";
});

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(webRootPath)
});

if ((builder.Configuration["Urls"] ?? string.Empty).Contains("https://", StringComparison.OrdinalIgnoreCase))
{
    app.UseHttpsRedirection();
}
app.UseRouting();
app.UseCors("FlutterDevCors");
// CORS must handle browser preflight before the API-key check.
app.UseMiddleware<ApiKeyMiddleware>();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
