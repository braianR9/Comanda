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
    .AddEnvironmentVariables();

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
builder.Services.AddHostedService<PrintJobWorker>();
builder.Services.AddScoped<SectorService>();
builder.Services.AddScoped<ProductoService>();
builder.Services.AddScoped<CatalogosService>();
builder.Services.AddScoped<StockMovementService>();
builder.Services.AddScoped<CustomerService>();
builder.Services.AddScoped<UsuarioService>();
builder.Services.AddScoped<ReportsService>();
builder.Services.AddSingleton<GoogleSheetsService>();
builder.Services.AddHostedService<GoogleSheetSyncWorker>();

// ─── Controllers ────────────────────────────────────────────────────────────
builder.Services.AddControllers()
    .AddNewtonsoftJson();

// ─── CORS para Flutter Web en desarrollo ───
builder.Services.AddCors(options =>
{
    options.AddPolicy("FlutterDevCors", policy =>
    {
        policy
            .WithOrigins(
                "http://localhost:3000",
                "http://127.0.0.1:3000"
            )
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
        Name = "X-Api-Key",
        Type = SecuritySchemeType.ApiKey,
        Scheme = "ApiKeyScheme",
        In = ParameterLocation.Header,
        Description = "Ingresá la API Key en el campo. Ejemplo: **focokey**"
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

// ─── Middleware de API Key ───────────────────────────────────────────────────
app.UseMiddleware<ApiKeyMiddleware>();

if ((builder.Configuration["Urls"] ?? string.Empty).Contains("https://", StringComparison.OrdinalIgnoreCase))
{
    app.UseHttpsRedirection();
}
app.UseRouting();
app.UseCors("FlutterDevCors");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
