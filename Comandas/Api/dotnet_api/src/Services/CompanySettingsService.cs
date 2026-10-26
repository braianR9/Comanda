using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
namespace BarIceCreamShop.Api.Services;
public class CompanySettingsService(AppDbContext db)
{
    public async Task<object> GetAsync(int company)
    {
        var empresa = await db.Empresas.AsNoTracking().SingleAsync(x => x.Id == company);
        var settings = await db.CompanySettings.AsNoTracking().SingleOrDefaultAsync(x => x.CompanyId == company);
        return new { Company = empresa, Address = settings?.Address ?? "", Website = settings?.Website ?? "",
            Billing = settings == null ? new BillingSettings { Cuit = empresa.Cuit ?? "" } : JsonSerializer.Deserialize<BillingSettings>(settings.BillingJson),
            Version = settings?.Version ?? 0, settings?.UpdatedAt };
    }
    public async Task<object> SaveAsync(int company, int user, CompanySettingsRequest request)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        var empresa = await db.Empresas.FromSqlInterpolated($"SELECT * FROM empresas WHERE id_empresa={company} FOR UPDATE").SingleAsync();
        var settings = await db.CompanySettings.SingleOrDefaultAsync(x => x.CompanyId == company);
        if ((settings?.Version ?? 0) != request.Version) throw new PurchaseException("La configuración cambió. Actualizá la pantalla antes de guardar.", 409);
        if (string.IsNullOrWhiteSpace(request.Name)) throw new PurchaseException("Indicá el nombre de la empresa.");
        if (request.Billing.Environment is not ("Homologacion" or "Produccion")) throw new PurchaseException("Ambiente de facturación inválido.");
        if (request.Billing.InvoicingMode is not ("Manual" or "Automatico")) throw new PurchaseException("Modo de facturación inválido.");
        request.Billing.Cuit = PurchaseService.NormalizeCuit(request.Billing.Cuit) ?? "";
        empresa.Nombre = request.Name.Trim(); empresa.Email = request.Email.Trim(); empresa.Telefono = request.Phone.Trim();
        empresa.Cuit = request.Billing.Cuit;
        if (settings == null) { settings = new CompanySettings { CompanyId = company, Version = 0 }; db.CompanySettings.Add(settings); }
        settings.Address = request.Address.Trim(); settings.Website = request.Website.Trim();
        settings.BillingJson = JsonSerializer.Serialize(request.Billing); settings.Version++;
        settings.UpdatedBy = user; settings.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(); await tx.CommitAsync();
        return await GetAsync(company);
    }
}
