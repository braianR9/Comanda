using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Npgsql;
namespace BarIceCreamShop.Api.Services;

public sealed class PurchaseException(string message, int statusCode = 400) : Exception(message)
{ public int StatusCode { get; } = statusCode; }

public class PurchaseService(AppDbContext db, StockMovementService stock)
{
    public Task<List<Supplier>> SuppliersAsync(int company) => db.Suppliers.AsNoTracking()
        .Where(x => x.CompanyId == company).OrderBy(x => x.Name).ToListAsync();

    public async Task<object> SupplierAsync(int company, int id)
    {
        var supplier = await db.Suppliers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == company)
            ?? throw new PurchaseException("Proveedor no encontrado.", 404);
        var products = await (from link in db.SupplierProducts join p in db.Productos on link.ProductId equals p.Id
            where link.SupplierId == id && p.IdEmpresa == company
            orderby p.Nombre select new { link.ProductId, Name = p.Nombre, link.Code, p.Activo }).ToListAsync();
        return new { Supplier = supplier, Products = products };
    }

    public async Task<Supplier> SaveSupplierAsync(int company, int? id, SupplierRequest request)
    {
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        if (string.IsNullOrWhiteSpace(request.Name)) throw new PurchaseException("Indicá el nombre del proveedor.");
        if (request.Products.Select(x => x.ProductId).Distinct().Count() != request.Products.Count)
            throw new PurchaseException("Hay productos repetidos en el proveedor.");
        var ids = request.Products.Select(x => x.ProductId).ToList();
        var products = await db.Productos.AsNoTracking().Where(x => ids.Contains(x.Id) && x.IdEmpresa == company).ToListAsync();
        if (products.Count != ids.Count || products.Any(p => !IsSimple(p)))
            throw new PurchaseException("Asociá únicamente productos simples de esta empresa.");
        var supplier = id.HasValue
            ? await db.Suppliers.FromSqlInterpolated($"SELECT * FROM proveedores WHERE id_proveedor={id} AND id_empresa={company} FOR UPDATE").SingleOrDefaultAsync()
                ?? throw new PurchaseException("Proveedor no encontrado.", 404)
            : new Supplier { CompanyId = company };
        if (id.HasValue && supplier.Version != request.Version) throw new PurchaseException("El proveedor cambió. Actualizá la pantalla.", 409);
        supplier.Name = request.Name.Trim(); supplier.Cuit = NormalizeCuit(request.Cuit);
        supplier.TaxCondition = request.TaxCondition.Trim(); supplier.Contact = request.Contact.Trim();
        supplier.Phone = request.Phone.Trim(); supplier.Email = request.Email.Trim();
        supplier.Address = request.Address.Trim(); supplier.Notes = request.Notes.Trim(); supplier.Active = request.Active;
        if (id.HasValue) supplier.Version++;
        else db.Suppliers.Add(supplier);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException e) when (Unique(e)) { throw new PurchaseException("Ya existe un proveedor con ese CUIT.", 409); }
        var links = await db.SupplierProducts.Where(x => x.SupplierId == supplier.Id).ToListAsync();
        db.SupplierProducts.RemoveRange(links.Where(x => !ids.Contains(x.ProductId)));
        foreach (var value in request.Products)
        {
            var link = links.FirstOrDefault(x => x.ProductId == value.ProductId);
            if (link == null) db.SupplierProducts.Add(new SupplierProduct { SupplierId = supplier.Id, ProductId = value.ProductId, Code = value.Code.Trim() });
            else link.Code = value.Code.Trim();
        }
        await db.SaveChangesAsync();
        if (tx != null) await tx.CommitAsync();
        return supplier;
    }

    public async Task<object> ListAsync(int company, int branch, string? status, int page = 1)
    {
        page = Math.Max(1, page);
        var query = db.Purchases.AsNoTracking().Where(x => x.CompanyId == company && x.BranchId == branch);
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(x => x.Status == status);
        var count = await query.CountAsync();
        var items = await query.OrderByDescending(x => x.Id).Skip((page - 1) * 30).Take(30)
            .Select(x => new { x.Id, x.SupplierName, x.DocumentType, x.Letter, x.PointOfSale, x.Number, x.DocumentDate,
                x.DocumentTotal, x.Status, x.Version, x.CreatedByName, x.CreatedAt, x.ControlledByName, x.ControlledAt }).ToListAsync();
        return new { Items = items, Page = page, TotalPages = (count + 29) / 30, TotalItems = count };
    }

    public async Task<object> GetAsync(int company, int branch, int id)
    {
        var purchase = await db.Purchases.AsNoTracking().Include(x => x.Items)
            .FirstOrDefaultAsync(x => x.Id == id && x.CompanyId == company && x.BranchId == branch)
            ?? throw new PurchaseException("Compra no encontrada.", 404);
        var history = await db.PurchaseAudits.AsNoTracking().Where(x => x.PurchaseId == id).OrderBy(x => x.Id).ToListAsync();
        return new { Purchase = purchase, History = history };
    }

    public async Task<object> SaveAsync(int company, int branch, int user, int? id, PurchaseRequest request)
    {
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        // Misma clave de solicitud: devuelve la compra original ante una respuesta perdida.
        if (!id.HasValue)
        {
            if (string.IsNullOrWhiteSpace(request.RequestKey)) throw new PurchaseException("Falta la identificación de la carga.");
            var existing = await db.Purchases.AsNoTracking().FirstOrDefaultAsync(x => x.CompanyId == company && x.RequestKey == request.RequestKey);
            if (existing != null) return await GetAsync(company, branch, existing.Id);
        }
        var purchase = id.HasValue ? await Locked(company, branch, id.Value) : new Purchase {
            CompanyId = company, BranchId = branch, CreatedBy = user, CreatedAt = DateTime.UtcNow,
            CreatedByName = await UserName(user), RequestKey = request.RequestKey
        };
        if (id.HasValue && (purchase.Status != "Borrador" || purchase.Version != request.Version))
            throw new PurchaseException("La compra cambió o ya no es un borrador. Actualizá la pantalla.", 409);
        var supplier = await db.Suppliers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == request.SupplierId && x.CompanyId == company && x.Active)
            ?? throw new PurchaseException("Seleccioná un proveedor activo.");
        if (request.DocumentType is not ("Factura" or "Remito")) throw new PurchaseException("El comprobante debe ser Factura o Remito.");
        if (request.DocumentDate == default || string.IsNullOrWhiteSpace(request.Number)) throw new PurchaseException("Indicá fecha y número del comprobante.");
        if (request.DocumentType == "Factura" && (request.PointOfSale <= 0 || request.Letter is not ("A" or "B" or "C" or "M" or "E")))
            throw new PurchaseException("Para una factura indicá letra y punto de venta.");
        await ValidateItems(company, supplier.Id, request.Items);
        purchase.SupplierId = supplier.Id; purchase.SupplierName = supplier.Name;
        purchase.DocumentType = request.DocumentType; purchase.Letter = request.DocumentType == "Factura" ? request.Letter : "";
        purchase.PointOfSale = request.PointOfSale; purchase.Number = request.Number.Trim().ToUpperInvariant();
        if (long.TryParse(purchase.Number, out var numericNumber)) purchase.Number = numericNumber.ToString();
        purchase.DocumentDate = request.DocumentDate; purchase.DocumentTotal = request.DocumentTotal;
        purchase.Notes = request.Notes.Trim();
        if (!id.HasValue) { db.Purchases.Add(purchase); }
        else purchase.Version++;
        var ids = request.Items.Select(x => x.ProductId).ToHashSet();
        var names = await db.Productos.Where(x => ids.Contains(x.Id) && x.IdEmpresa == company).ToDictionaryAsync(x => x.Id, x => x.Nombre);
        var oldItems = purchase.Items.ToList();
        foreach (var removed in oldItems.Where(x => !ids.Contains(x.ProductId))) { db.PurchaseItems.Remove(removed); purchase.Items.Remove(removed); }
        foreach (var row in request.Items)
        {
            var item = oldItems.FirstOrDefault(x => x.ProductId == row.ProductId);
            if (item == null) { item = new PurchaseItem { ProductId = row.ProductId }; purchase.Items.Add(item); }
            item.ProductName = names[row.ProductId]; item.Quantity = row.Quantity; item.UnitCost = row.UnitCost;
        }
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException e) when (Unique(e)) { throw new PurchaseException("Este comprobante ya está cargado para el proveedor. Revisá el listado de compras.", 409); }
        await Audit(purchase, user, id.HasValue ? "Modificada" : "Creada", "");
        await db.SaveChangesAsync();
        if (tx != null) await tx.CommitAsync();
        return await GetAsync(company, branch, purchase.Id);
    }

    public async Task<object> ControlAsync(int company, int branch, int user, int id, PurchaseActionRequest request)
    {
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var purchase = await Locked(company, branch, id);
        if (purchase.Status == "Controlado") return await GetAsync(company, branch, id);
        if (purchase.Status != "Borrador" || purchase.Version != request.Version) throw new PurchaseException("La compra cambió. Actualizá antes de controlar.", 409);
        if (!await db.Suppliers.AnyAsync(x => x.Id == purchase.SupplierId && x.CompanyId == company && x.Active))
            throw new PurchaseException("El proveedor está inactivo.");
        await ValidateItems(company, purchase.SupplierId, purchase.Items.Select(x => new PurchaseItemRequest(x.ProductId, x.Quantity, x.UnitCost)).ToList());
        foreach (var item in purchase.Items.OrderBy(x => x.ProductId))
            await stock.ReceivePurchaseAsync(company, branch, user, purchase.Id, item.ProductId, item.Quantity,
                $"Compra {purchase.Id}: {purchase.DocumentType} {purchase.PointOfSale:D5}-{purchase.Number} · {purchase.SupplierName}");
        purchase.Status = "Controlado"; purchase.Version++; purchase.ControlledBy = user;
        purchase.ControlledByName = await UserName(user); purchase.ControlledAt = DateTime.UtcNow;
        await Audit(purchase, user, "Controlada e ingresada al stock", request.Reason);
        await db.SaveChangesAsync();
        if (tx != null) await tx.CommitAsync();
        return await GetAsync(company, branch, id);
    }

    public async Task<object> CancelAsync(int company, int branch, int user, int id, PurchaseActionRequest request)
    {
        await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
        var purchase = await Locked(company, branch, id);
        if (purchase.Status != "Borrador" || purchase.Version != request.Version) throw new PurchaseException("Sólo se pueden anular borradores sin cambios concurrentes.", 409);
        if (string.IsNullOrWhiteSpace(request.Reason)) throw new PurchaseException("Indicá el motivo de anulación.");
        purchase.Status = "Anulado"; purchase.Version++;
        await Audit(purchase, user, "Anulada", request.Reason);
        await db.SaveChangesAsync();
        if (tx != null) await tx.CommitAsync();
        return await GetAsync(company, branch, id);
    }

    private async Task ValidateItems(int company, int supplier, List<PurchaseItemRequest> items)
    {
        if (items.Count == 0 || items.Count > 200 || items.Select(x => x.ProductId).Distinct().Count() != items.Count)
            throw new PurchaseException("Agregá entre 1 y 200 productos, sin repetirlos.");
        if (items.Any(x => x.Quantity <= 0 || x.Quantity > 999999999999.999m || decimal.Round(x.Quantity, 3) != x.Quantity || x.UnitCost < 0 || x.UnitCost > 9999999999999.99m || decimal.Round(x.UnitCost,2) != x.UnitCost))
            throw new PurchaseException("Revisá las cantidades (hasta 3 decimales) y costos (hasta 2 decimales).");
        var ids = items.Select(x => x.ProductId).ToList();
        var products = await (from link in db.SupplierProducts join p in db.Productos on link.ProductId equals p.Id
            where link.SupplierId == supplier && ids.Contains(p.Id) && p.IdEmpresa == company && p.Activo select p).ToListAsync();
        if (products.Count != ids.Count || products.Any(p => !IsSimple(p)))
            throw new PurchaseException("Los productos deben ser simples, activos y estar asociados a este proveedor.");
    }
    private async Task<Purchase> Locked(int company, int branch, int id)
    {
        var purchase = await db.Purchases.FromSqlInterpolated($"SELECT * FROM compras WHERE id_compra={id} AND id_empresa={company} AND id_sucursal={branch} FOR UPDATE").SingleOrDefaultAsync()
            ?? throw new PurchaseException("Compra no encontrada.", 404);
        await db.Entry(purchase).Collection(x => x.Items).LoadAsync();
        return purchase;
    }
    private Task<string> UserName(int user) => db.Usuarios.Where(x => x.Id == user).Select(x => x.Nombre + " " + x.Apellido).SingleAsync();
    private async Task Audit(Purchase purchase, int user, string action, string reason) => db.PurchaseAudits.Add(new PurchaseAudit {
        PurchaseId = purchase.Id, UserId = user, UserName = await UserName(user), Date = DateTime.UtcNow,
        Action = action, Reason = reason.Trim(), Snapshot = JsonSerializer.Serialize(purchase)
    });
    private static bool IsSimple(Producto p) => p.TipoProducto.Replace(" ", "").Equals("ProductoSimple", StringComparison.OrdinalIgnoreCase);
    private static bool Unique(DbUpdateException e) => e.InnerException is PostgresException { SqlState: "23505" };
    public static string? NormalizeCuit(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var digits = value.Replace("-", "").Replace(" ", "");
        if (digits.Length != 11 || !digits.All(char.IsAsciiDigit)) throw new PurchaseException("El CUIT debe tener 11 dígitos.");
        return digits;
    }
}
