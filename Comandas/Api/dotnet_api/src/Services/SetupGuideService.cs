using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

/// Paso de la guía de puesta en marcha: qué falta configurar antes de operar.
public record SetupStep(string Key, string Title, string Detail, bool Done, bool Optional);

/// Revisa la configuración de la empresa y la sucursal para la guía de puesta en marcha.
public class SetupGuideService(AppDbContext db)
{
    public async Task<object> StatusAsync(int company, int branch)
    {
        var empresa = await db.Empresas.AsNoTracking().SingleAsync(x => x.Id == company);
        var settings = await db.CompanySettings.AsNoTracking().SingleOrDefaultAsync(x => x.CompanyId == company);
        var billing = settings == null ? new BillingSettings()
            : JsonSerializer.Deserialize<BillingSettings>(settings.BillingJson) ?? new BillingSettings();

        var printers = await db.PrinterConfigurations.CountAsync(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Activa);
        var tables = await db.Tables.CountAsync(x => x.IdEmpresa == company && x.IdSucursal == branch && x.Activo && !x.EsMostrador);
        var groups = await db.Rubros.CountAsync(x => x.IdEmpresa == company && x.Activo);
        var products = await db.Productos.CountAsync(x => x.IdEmpresa == company && x.Activo);
        var cards = await db.Cards.CountAsync(x => x.IdEmpresa == company && x.Activa);
        var users = await db.Usuarios.CountAsync(x => x.IdEmpresa == company && x.Activo);
        var certificate = await db.AfipCredentials.AsNoTracking()
            .SingleOrDefaultAsync(x => x.CompanyId == company && x.Environment == "Produccion");

        var missingCompany = Missing(
            (string.IsNullOrWhiteSpace(empresa.Nombre), "nombre comercial"),
            (string.IsNullOrWhiteSpace(empresa.Telefono), "teléfono"),
            (string.IsNullOrWhiteSpace(settings?.Address), "dirección"));
        var missingFiscal = Missing(
            (string.IsNullOrWhiteSpace(billing.LegalName), "razón social"),
            (string.IsNullOrWhiteSpace(billing.Cuit), "CUIT"),
            (string.IsNullOrWhiteSpace(billing.TaxCondition), "condición frente al IVA"),
            (string.IsNullOrWhiteSpace(billing.FiscalAddress), "domicilio fiscal"),
            (billing.PointOfSale == null, "punto de venta"));
        var certificateOk = certificate?.Certificate != null
            && (certificate.CertificateExpiresAt == null || certificate.CertificateExpiresAt > DateTime.UtcNow);
        var production = billing.Environment == "Produccion";

        var steps = new List<SetupStep>
        {
            new("empresa", "Datos del local",
                missingCompany ?? "Nombre, teléfono y dirección cargados.", missingCompany == null, false),
            new("mesas", "Sectores y mesas",
                tables == 0 ? "Creá los sectores del salón y agregá las mesas." : $"{tables} {Plural(tables, "mesa", "mesas")} en esta sucursal.",
                tables > 0, false),
            new("rubros", "Rubros",
                groups == 0 ? "Creá los rubros para ordenar la carta (por ejemplo Bebidas, Platos, Postres)." : $"{groups} {Plural(groups, "rubro", "rubros")}.",
                groups > 0, false),
            new("productos", "Productos y precios",
                products == 0 ? "Cargá los productos con su precio, a mano o importando un Excel." : $"{products} {Plural(products, "producto activo", "productos activos")}.",
                products > 0, false),
            new("impresoras", "Impresoras",
                printers == 0 ? "Configurá la impresora de tickets y la de comandas de esta sucursal." : $"{printers} {Plural(printers, "impresora configurada", "impresoras configuradas")}.",
                printers > 0, false),
            new("pagos", "Tipos de pago",
                cards == 0 ? "Cargá los tipos de pago con los que te pagan los clientes (efectivo, débito, crédito, Mercado Pago…), con su recargo o descuento." : $"{cards} {Plural(cards, "tipo de pago", "tipos de pago")}.",
                cards > 0, false),
            new("usuarios", "Usuarios del personal",
                users <= 1 ? "Creá usuarios para mozos y cajeros, cada uno con su rol." : $"{users} usuarios activos.",
                users > 1, true),
            new("fiscal", "Datos fiscales",
                missingFiscal ?? "Datos para la factura electrónica completos.", missingFiscal == null, true),
            new("arca", "Factura electrónica de ARCA",
                !certificateOk
                    ? certificate?.Certificate != null ? "El certificado de producción venció: generá uno nuevo." : "Cargá el certificado de producción de ARCA y probá la conexión."
                    : !production ? "Certificado listo. Cambiá el ambiente de ARCA a Producción para emitir facturas reales."
                    : "Facturando en producción.",
                certificateOk && production, true),
        };

        return new
        {
            steps,
            pendingRequired = steps.Count(x => !x.Done && !x.Optional),
            pendingOptional = steps.Count(x => !x.Done && x.Optional),
        };
    }

    private static string? Missing(params (bool missing, string label)[] fields)
    {
        var list = fields.Where(x => x.missing).Select(x => x.label).ToList();
        return list.Count == 0 ? null : $"Falta: {string.Join(", ", list)}.";
    }

    private static string Plural(int count, string one, string many) => count == 1 ? one : many;
}
