using BarIceCreamShop.Api.Data; using BarIceCreamShop.Api.Models; using Microsoft.EntityFrameworkCore;
namespace BarIceCreamShop.Api.Services;
public sealed class StockMovementService(AppDbContext db)
{
 public async Task<List<StockMovementDto>> ListAsync(int company,int branch,DateTime? from,DateTime? to,int? productId,string? type){var q=from x in db.StockMovements.AsNoTracking() join p in db.Productos on x.ProductId equals p.Id join u in db.Usuarios on x.UserId equals u.Id where x.CompanyId==company&&x.BranchId==branch select new{x,p,u};if(from.HasValue){var fromUtc=AsUtc(from.Value);q=q.Where(v=>v.x.Date>=fromUtc);}if(to.HasValue){var toUtc=AsUtc(to.Value);q=q.Where(v=>v.x.Date<=toUtc);}if(productId.HasValue)q=q.Where(v=>v.x.ProductId==productId);if(!string.IsNullOrWhiteSpace(type)){var normalized=NormalizeType(type);q=q.Where(v=>v.x.Type==normalized);}var rows=await q.OrderByDescending(v=>v.x.Date).Take(1000).ToListAsync();var saleIds=rows.Where(v=>(v.x.Source=="Venta"||v.x.Source=="Compuesto")&&v.x.ReferenceId!=null).Select(v=>v.x.ReferenceId!.Value).Distinct().ToList();var printedNumbers=saleIds.Count==0?new Dictionary<int,int>():await db.Orders.AsNoTracking().Include(o=>o.Commands).Where(o=>saleIds.Contains(o.Id)).ToDictionaryAsync(o=>o.Id,o=>o.PrintedNumber);return rows.Select(v=>new StockMovementDto(v.x.Id,v.x.Date,v.x.ProductId,v.p.Nombre,v.x.Type,v.x.Quantity,v.x.PreviousStock,v.x.NewStock,v.x.Source,v.x.ReferenceId,v.x.Note,v.u.Nombre+" "+v.u.Apellido,v.x.ReferenceId!=null&&printedNumbers.TryGetValue(v.x.ReferenceId.Value,out var n)?n:null)).ToList();}
 public async Task<StockMovementDto> AdjustAsync(int company,int branch,int user,StockAdjustmentRequest r){var type=NormalizeType(r.Type);var product=await db.Productos.SingleOrDefaultAsync(p=>p.Id==r.ProductId&&p.IdEmpresa==company)??throw new SaleException("Producto no encontrado.",404);await using var tx=await db.Database.BeginTransactionAsync();var movement=await ApplyAsync(company,branch,user,product,type,r.Quantity,"Manual",null,r.Note)
     ?? throw new InvalidOperationException("No se pudo registrar el movimiento manual.");await db.SaveChangesAsync();await tx.CommitAsync();return new(movement.Id,movement.Date,product.Id,product.Nombre,movement.Type,movement.Quantity,movement.PreviousStock,movement.NewStock,movement.Source,null,movement.Note,"Usuario actual",null);}
 public async Task ApplySaleAsync(Order sale,int user){if(await db.StockMovements.AnyAsync(x=>x.BranchId==sale.IdSucursal&&x.ReferenceId==sale.Id&&(x.Source=="Venta"||x.Source=="Compuesto")))return;foreach(var item in sale.Items.Where(i=>i.Estado=="Activo")){var product=await db.Productos.AsNoTracking().SingleAsync(p=>p.Id==item.ProductId);if(product.TipoProducto.Contains("compuesto",StringComparison.OrdinalIgnoreCase)){var parts=await db.ProductComponents.Where(x=>x.CompositeProductId==product.Id).ToListAsync();if(parts.Count==0)throw new SaleException($"El producto compuesto {product.Nombre} no tiene componentes configurados.",409);foreach(var part in parts){var component=await db.Productos.AsNoTracking().SingleOrDefaultAsync(p=>p.Id==part.ComponentProductId&&p.IdEmpresa==sale.IdEmpresa);if(component==null||!IsSimple(component)||!component.Activo)throw new SaleException($"Revisá la composición de {product.Nombre}: sus componentes deben ser simples y activos.",409);await ApplyAsync(sale.IdEmpresa,sale.IdSucursal,user,component,"Egreso",part.Quantity*item.Quantity,"Compuesto",sale.Id,$"Pedido {sale.PrintedNumber}: {product.Nombre}");}}else await ApplyAsync(sale.IdEmpresa,sale.IdSucursal,user,product,"Egreso",item.Quantity,"Venta",sale.Id,$"Pedido {sale.PrintedNumber}");}}
 // Validate the complete proposed order before changing its selected quantities.
 public async Task ReverseSaleAsync(int company, int branch, int user, int saleId, string reason)
 {
     if (db.Database.CurrentTransaction == null) throw new InvalidOperationException("La reposición requiere una transacción.");
     var original = await db.StockMovements.AsNoTracking().Where(m => m.CompanyId == company && m.BranchId == branch &&
         m.ReferenceId == saleId && (m.Source == "Venta" || m.Source == "Compuesto") && m.Type == "Egreso").ToListAsync();
     foreach (var group in original.GroupBy(m => m.ProductId).OrderBy(g => g.Key))
     {
         // Se revierte lo efectivamente descontado, incluso si se agotó un stock sin bloqueo.
         var quantity = group.Sum(m => Math.Max(0, m.PreviousStock - m.NewStock));
         if (quantity == 0) continue;
         var row = await db.StockProductos.FromSqlInterpolated(
             $"SELECT * FROM stock_productos WHERE id_producto={group.Key} AND id_sucursal={branch} FOR UPDATE").SingleOrDefaultAsync()
             ?? throw new SaleException("Falta la configuración de stock de un producto vendido. Restaurala antes de anular.", 409);
         var previous = row.StockActual;
         row.StockActual += quantity; row.FechaModificacion = DateTime.UtcNow;
         var note = $"Anulación de venta {saleId}: {reason}";
         db.StockMovements.Add(new StockMovement { CompanyId = company, BranchId = branch, ProductId = group.Key,
             Type = "Ingreso", Quantity = quantity, PreviousStock = previous, NewStock = row.StockActual,
             Source = "AnulacionVenta", ReferenceId = saleId, Note = note[..Math.Min(note.Length, 500)], UserId = user, Date = DateTime.UtcNow });
     }
 }

 public async Task ValidateSelectionAsync(int company, int branch, IEnumerable<SaleItemRequest> selection)
 {
     var lines = selection.ToList();
     if (lines.Any(l => l.Quantity <= 0 || decimal.Round(l.Quantity, 3) != l.Quantity))
         throw new SaleException("Las cantidades deben ser positivas y tener como máximo tres decimales.");
     var ids = lines.Select(l => l.ProductId).Distinct().ToList();
     var products = await db.Productos.AsNoTracking().Where(p => ids.Contains(p.Id) && p.IdEmpresa == company && p.Activo)
         .ToDictionaryAsync(p => p.Id);
     if (products.Count != ids.Count) throw new SaleException("Hay productos no disponibles para el pedido.", 409);
     var compoundIds = products.Values.Where(p => !IsSimple(p)).Select(p => p.Id).ToList();
     var parts = await db.ProductComponents.AsNoTracking().Where(p => compoundIds.Contains(p.CompositeProductId)).ToListAsync();
     var required = new Dictionary<int, decimal>();
     void Add(int product, decimal quantity) => required[product] = required.GetValueOrDefault(product) + quantity;
     foreach (var line in lines)
     {
         if (IsSimple(products[line.ProductId])) { Add(line.ProductId, line.Quantity); continue; }
         var components = parts.Where(p => p.CompositeProductId == line.ProductId).ToList();
         if (components.Count == 0) throw new SaleException($"El producto compuesto {products[line.ProductId].Nombre} no tiene componentes configurados.", 409);
         foreach (var part in components) Add(part.ComponentProductId, part.Quantity * line.Quantity);
     }
     var requiredIds = required.Keys.ToList();
     var componentsById = await db.Productos.AsNoTracking()
         .Where(p => requiredIds.Contains(p.Id) && p.IdEmpresa == company && p.Activo).ToDictionaryAsync(p => p.Id);
     if (componentsById.Count != requiredIds.Count || componentsById.Values.Any(p => !IsSimple(p)))
         throw new SaleException("Revisá la composición del pedido: los componentes deben ser productos simples y activos.", 409);
     var stocks = await db.StockProductos.AsNoTracking()
         .Where(s => s.IdSucursal == branch && requiredIds.Contains(s.IdProducto)).ToListAsync();
     foreach (var stock in stocks)
     {
         var quantity = required[stock.IdProducto];
         if (stock.ComprobarStockAlVender && quantity > stock.StockActual)
             throw new SaleException($"Stock insuficiente para {componentsById[stock.IdProducto].Nombre}. Disponible: {stock.StockActual}; cantidad en el pedido: {quantity}.", 409);
     }
 }

 public async Task<List<ProductComponentDto>> ComponentsAsync(int company,int productId)=>await(from c in db.ProductComponents join p in db.Productos on c.ComponentProductId equals p.Id where c.CompositeProductId==productId&&p.IdEmpresa==company select new ProductComponentDto(p.Id,p.Nombre,c.Quantity)).ToListAsync();
 public async Task ValidateComponentsAsync(int company, int productId, List<ProductComponentRequest> values)
 {
     if (values.Count == 0) throw new SaleException("Agregá al menos un producto simple a la composición.");
     if (values.Any(x => x.ProductId == productId) || values.GroupBy(x => x.ProductId).Any(g => g.Count() > 1))
         throw new SaleException("La composición contiene productos repetidos o una referencia a sí misma.");
     if (values.Any(x => x.Quantity <= 0 || x.Quantity > 999999999999999.999m || decimal.Round(x.Quantity, 3) != x.Quantity))
         throw new SaleException("Las cantidades deben ser positivas y tener como máximo tres decimales.");
     var ids = values.Select(x => x.ProductId).ToList();
     var products = await db.Productos.AsNoTracking().Where(p => ids.Contains(p.Id) && p.IdEmpresa == company && p.Activo).ToListAsync();
     if (products.Count != ids.Count || products.Any(p => !IsSimple(p)))
         throw new SaleException("Los componentes deben ser productos simples activos de la misma empresa.");
 }

 private static bool IsSimple(Producto product) => product.TipoProducto.Replace(" ", "").Equals("ProductoSimple", StringComparison.OrdinalIgnoreCase);

 public async Task<List<ProductComponentDto>> SaveComponentsAsync(int company, int productId, List<ProductComponentRequest> values)
 {
     await using var tx = db.Database.CurrentTransaction == null ? await db.Database.BeginTransactionAsync() : null;
     var product = await db.Productos.SingleOrDefaultAsync(p => p.Id == productId && p.IdEmpresa == company)
         ?? throw new SaleException("Producto no encontrado.", 404);
     if (!product.TipoProducto.Contains("compuesto", StringComparison.OrdinalIgnoreCase))
         throw new SaleException("Sólo un producto compuesto puede tener componentes.");
     await ValidateComponentsAsync(company, productId, values);
     var existing = await db.ProductComponents.Where(x => x.CompositeProductId == productId).ToListAsync();
     db.ProductComponents.RemoveRange(existing.Where(x => !values.Any(v => v.ProductId == x.ComponentProductId)));
     foreach (var value in values)
     {
         var part = existing.SingleOrDefault(x => x.ComponentProductId == value.ProductId);
         if (part == null) db.ProductComponents.Add(new ProductComponent { CompositeProductId = productId, ComponentProductId = value.ProductId, Quantity = value.Quantity });
         else part.Quantity = value.Quantity;
     }
     await db.SaveChangesAsync();
     if (tx != null) await tx.CommitAsync();
     return await ComponentsAsync(company, productId);
 }
 public async Task ReceivePurchaseAsync(int company, int branch, int user, int purchase, int productId, decimal quantity, string note)
 {
     if (db.Database.CurrentTransaction == null) throw new InvalidOperationException("El ingreso de compra requiere una transacción.");
     var product = await db.Productos.AsNoTracking().SingleOrDefaultAsync(x => x.Id == productId && x.IdEmpresa == company && x.Activo)
         ?? throw new SaleException("Producto no disponible para ingreso.", 409);
     await ApplyAsync(company, branch, user, product, "Ingreso", quantity, "Compra", purchase, note.Length > 500 ? note[..500] : note);
 }
 private async Task<StockMovement?> ApplyAsync(int company, int branch, int user, Producto product,
     string type, decimal quantity, string source, int? reference, string? note)
 {
     var stock = await db.StockProductos.FromSqlInterpolated(
         $"SELECT * FROM stock_productos WHERE id_producto={product.Id} AND id_sucursal={branch} FOR UPDATE")
         .SingleOrDefaultAsync();
     if (stock == null)
     {
         // No branch configuration means this product has no sale stock control.
         // Imports intentionally leave stock unconfigured. Manual movements and
         // purchases still need a configured stock record to update.
         if (source is "Venta" or "Compuesto") return null;
         throw new SaleException($"{product.Nombre} no tiene stock configurado en la sucursal. Configuralo antes de registrar movimientos.", 409);
     }
     quantity = decimal.Round(quantity, 3);
     if (stock.OperacionCantidad == "Entero" && quantity != decimal.Truncate(quantity))
         throw new SaleException($"{product.Nombre} sólo admite cantidades enteras.", 409);
     var previous = stock.StockActual;
     var next = type == "Ingreso" ? previous + quantity : type == "Egreso" ? previous - quantity : quantity;
     // Sale quantities were checked when selected, before preparation/payment.
     if (next < 0 && source == "Manual")
         throw new SaleException($"Stock insuficiente para {product.Nombre}. Disponible: {previous}; egreso solicitado: {quantity}.", 409);
     next = Math.Max(0, next);
     var movementQuantity = type == "Ajuste" ? Math.Abs(next - previous) : quantity;
     if (movementQuantity == 0)
         throw new SaleException($"El ajuste no modifica el stock de {product.Nombre}.", 409);
     stock.StockActual = next;
     stock.FechaModificacion = DateTime.UtcNow;
     var movement = new StockMovement {
         CompanyId = company, BranchId = branch, ProductId = product.Id, Type = type,
         Quantity = movementQuantity, PreviousStock = previous, NewStock = next,
         Source = source, ReferenceId = reference, Note = note?.Trim(), UserId = user, Date = DateTime.UtcNow
     };
     db.StockMovements.Add(movement);
     return movement;
 }
 private static string NormalizeType(string? value)=>value?.Trim().ToLowerInvariant() switch{"ingreso"=>"Ingreso","egreso"=>"Egreso","ajuste"=>"Ajuste",_=>throw new SaleException("El tipo debe ser Ingreso, Egreso o Ajuste.")};
 private static DateTime AsUtc(DateTime value)=>value.Kind switch{DateTimeKind.Utc=>value,DateTimeKind.Local=>value.ToUniversalTime(),_=>DateTime.SpecifyKind(value,DateTimeKind.Utc)};
}
