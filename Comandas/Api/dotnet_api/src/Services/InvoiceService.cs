using System.Text;
using System.Text.Json;
using BarIceCreamShop.Api.Data;
using BarIceCreamShop.Api.Models;
using Microsoft.EntityFrameworkCore;
using Npgsql;
namespace BarIceCreamShop.Api.Services;

/// Emisión de facturas y notas de crédito electrónicas de ventas finalizadas.
public class InvoiceService(AppDbContext db, AfipClient afip, AfipCredentialService credentials, IConfiguration configuration, ILogger<InvoiceService> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly int[] InvoiceTypes = [AfipCodes.FacturaA, AfipCodes.FacturaB, AfipCodes.FacturaC];

    public async Task<List<InvoiceDto>> ForSaleAsync(int company, int branch, int saleId)
    {
        await RequireSale(company, branch, saleId);
        var cuit = await CuitAsync(company);
        var rows = await db.Invoices.AsNoTracking().Where(x => x.CompanyId == company && x.OrderId == saleId)
            .OrderBy(x => x.Id).ToListAsync();
        var names = await NamesAsync(rows.Select(x => x.UserId));
        return rows.Select(x => Map(x, cuit, names)).ToList();
    }

    /// Comprobantes de la sucursal, del más reciente al más antiguo.
    public async Task<object> ListAsync(int company, int branch, int page)
    {
        page = Math.Max(page, 1);
        const int size = 50;
        var cuit = await CuitAsync(company);
        var query = db.Invoices.AsNoTracking().Where(x => x.CompanyId == company && x.BranchId == branch);
        var total = await query.CountAsync();
        var rows = await (from x in query.OrderByDescending(x => x.Id).Skip((page - 1) * size).Take(size)
                          join o in db.Orders on x.OrderId equals o.Id
                          select new { x, o.Numero }).ToListAsync();
        // Una venta sin factura vigente se puede volver a intentar.
        var saleIds = rows.Select(r => r.x.OrderId).Distinct().ToList();
        var invoiced = await db.Invoices.AsNoTracking()
            .Where(x => saleIds.Contains(x.OrderId) && InvoiceTypes.Contains(x.Type) && x.Status == "Autorizado" && x.CreditNoteId == null)
            .Select(x => x.OrderId).ToListAsync();
        // Quién y cuándo anuló cada factura, aunque la nota de crédito esté en otra página.
        var noteIds = rows.Where(r => r.x.CreditNoteId != null).Select(r => r.x.CreditNoteId!.Value).ToList();
        var notes = await db.Invoices.AsNoTracking().Where(x => noteIds.Contains(x.Id)).ToDictionaryAsync(x => x.Id);
        var invoiceIds = rows.Select(r => r.x.Id).ToList();
        var reprints = (await db.PrintJobs.AsNoTracking().Where(j => j.Reprint && j.InvoiceId != null && invoiceIds.Contains(j.InvoiceId.Value))
                .Select(j => new { InvoiceId = j.InvoiceId!.Value, j.UserId, j.CreatedAt }).ToListAsync())
            .GroupBy(j => j.InvoiceId).ToDictionary(g => g.Key, g => g.OrderByDescending(j => j.CreatedAt).ToList());
        var names = await NamesAsync(rows.Select(r => r.x.UserId).Concat(notes.Values.Select(n => n.UserId))
            .Concat(reprints.Values.SelectMany(g => g).Select(j => j.UserId ?? 0)));
        return new
        {
            page, totalPages = (int)Math.Ceiling(total / (double)size), totalItems = total,
            items = rows.Select(r =>
            {
                var note = r.x.CreditNoteId is { } id && notes.TryGetValue(id, out var n) ? n : null;
                var printed = reprints.GetValueOrDefault(r.x.Id);
                return new
                {
                    invoice = Map(r.x, cuit, names), saleNumber = r.Numero, canRetry = !invoiced.Contains(r.x.OrderId),
                    reprints = printed == null ? null : new
                    {
                        count = printed.Count, lastAt = printed[0].CreatedAt,
                        lastUserName = names.GetValueOrDefault(printed[0].UserId ?? 0, ""),
                    },
                    annulment = note == null ? null : new
                    {
                        number = $"{AfipCodes.TypeName(note.Type)} {Format(note)}",
                        userName = names.GetValueOrDefault(note.UserId, ""), at = note.AuthorizedAt ?? note.CreatedAt, reason = note.Reason,
                    },
                };
            }),
        };
    }

    /// Ventas cobradas sin factura vigente (nunca facturadas, rechazadas o anuladas con nota de crédito).
    public async Task<object> PendingAsync(int company, int branch, int page)
    {
        page = Math.Max(page, 1);
        const int size = 50;
        var query = db.Orders.AsNoTracking().Where(o => o.IdEmpresa == company && o.IdSucursal == branch && o.Estado == "Finalizada"
            && !db.Invoices.Any(x => x.OrderId == o.Id && InvoiceTypes.Contains(x.Type) && x.Status == "Autorizado" && x.CreditNoteId == null));
        var total = await query.CountAsync();
        var rows = await query.OrderByDescending(o => o.FechaCierre).ThenByDescending(o => o.Id)
            .Skip((page - 1) * size).Take(size)
            .Select(o => new
            {
                o.Id, o.Numero, o.FechaCierre, o.Total, o.Version, table = o.Table.Nombre, o.UsuarioCobroId,
                canVoid = !db.Invoices.Any(i => i.OrderId == o.Id && i.Status != "Rechazado"),
                lastAttempt = db.Invoices.Where(x => x.OrderId == o.Id).OrderByDescending(x => x.Id)
                    .Select(x => new { x.Status, x.Messages, x.CreatedAt, x.UserId, x.CreditNoteId }).FirstOrDefault(),
            }).ToListAsync();
        var names = await NamesAsync(rows.Select(r => r.UsuarioCobroId ?? 0).Concat(rows.Select(r => r.lastAttempt?.UserId ?? 0)));
        return new
        {
            page, totalPages = (int)Math.Ceiling(total / (double)size), totalItems = total,
            items = rows.Select(r => new
            {
                saleId = r.Id, saleNumber = r.Numero, closedAt = r.FechaCierre, r.Total, r.table,
                version = r.Version, r.canVoid,
                cashier = names.GetValueOrDefault(r.UsuarioCobroId ?? 0, ""),
                lastAttempt = r.lastAttempt == null ? null : new
                {
                    status = r.lastAttempt.Status == "Autorizado" && r.lastAttempt.CreditNoteId != null ? "Anulada" : r.lastAttempt.Status,
                    r.lastAttempt.Messages, at = r.lastAttempt.CreatedAt, userName = names.GetValueOrDefault(r.lastAttempt.UserId, ""),
                },
            }),
        };
    }

    /// Lo que necesita la caja para ofrecer facturar: si está lista y en qué modo.
    public async Task<object> ConfigurationAsync(int company)
    {
        var (missing, billing) = await ReadinessAsync(company);
        return new { ready = missing == null, mode = billing?.InvoicingMode ?? "Manual", environment = billing?.Environment ?? "Homologacion", missing };
    }

    /// Qué falta para poder facturar (null si está todo listo).
    private async Task<(string? Missing, BillingSettings? Billing)> ReadinessAsync(int company)
    {
        BillingSettings billing;
        try { billing = await credentials.BillingAsync(company); }
        catch (InvoiceException) { return ("datos de facturación", null); }
        var hasCertificate = await db.AfipCredentials.AsNoTracking().AnyAsync(x => x.CompanyId == company
            && x.Environment == billing.Environment && x.Certificate != null && x.CertificateExpiresAt > DateTime.UtcNow);
        var missing = !ValidCuit(billing.Cuit) ? "CUIT" : billing.PointOfSale is null ? "punto de venta"
            : string.IsNullOrWhiteSpace(billing.TaxCondition) ? "condición frente al IVA" : !hasCertificate ? "certificado de AFIP" : null;
        return (missing, billing);
    }

    /// Ticket de pago (no fiscal) de una venta cobrada; si ya tiene factura vigente, se imprime la factura.
    public async Task<object> PrintPaymentTicketAsync(int company, int branch, int user, int saleId)
    {
        var sale = await RequireSale(company, branch, saleId);
        if (sale.Estado != "Finalizada") throw new InvoiceException("Solo se imprime el ticket de ventas cobradas.", 409);
        await EnqueuePrintAsync(saleId, userId: user);
        return new { queued = true };
    }

    /// Factura una venta finalizada. Si quedó un intento sin confirmar, primero lo verifica en AFIP.
    public async Task<InvoiceDto> InvoiceSaleAsync(int company, int branch, int user, int saleId, InvoiceRequest request, bool print = true)
    {
        await using var fiscalLock = await SaleFiscalLock.AcquireAsync(db, saleId);
        var sale = await RequireSale(company, branch, saleId);
        if (sale.Estado != "Finalizada") throw new InvoiceException("Solo se facturan ventas cobradas.", 409);
        var billing = await RequireBilling(company);

        var current = await db.Invoices.AsNoTracking()
            .Where(x => x.OrderId == saleId && InvoiceTypes.Contains(x.Type) && x.Status != "Rechazado" && x.CreditNoteId == null)
            .FirstOrDefaultAsync();
        if (current?.Status == "Autorizado") throw new InvoiceException($"La venta ya tiene {AfipCodes.TypeName(current.Type)} {Format(current)}.", 409);

        var receiver = await ReceiverAsync(company, sale, request);
        var type = InvoiceType(billing, receiver.VatCondition);
        if (type == AfipCodes.FacturaA && receiver.DocType != AfipCodes.DocCuit)
            throw new InvoiceException("La factura A requiere un cliente con CUIT.");
        if (receiver.DocType == AfipCodes.DocSinIdentificar && sale.Total >= IdentificationThreshold())
            throw new InvoiceException($"Para facturar {Money(sale.Total)} o más a consumidor final hay que identificar al comprador (DNI, CUIL o CUIT).");

        var lines = await (from item in db.Orders.Where(o => o.Id == saleId).SelectMany(o => o.Items)
                           where item.Estado == "Activo"
                           join product in db.Productos on item.ProductId equals product.Id
                           select new { item.Subtotal, product.Alicuota.Porcentaje }).ToListAsync();
        var (net, vat, detail) = SplitVat(sale.Total, lines.Select(l => (l.Subtotal, l.Porcentaje)), Discriminates(type));

        var draft = new Invoice
        {
            CompanyId = company, BranchId = branch, OrderId = saleId, Environment = billing.Environment,
            Type = type, PointOfSale = billing.PointOfSale!.Value, Concept = billing.Concept,
            DocType = receiver.DocType, DocNumber = receiver.DocNumber, ReceiverName = receiver.Name,
            ReceiverVatCondition = receiver.VatCondition, CustomerId = receiver.CustomerId,
            Total = sale.Total, Net = net, Vat = vat, VatJson = JsonSerializer.Serialize(detail, Json), UserId = user,
        };
        var issued = await IssueAsync(company, billing, draft, associated: null);
        if (receiver.CustomerId.HasValue)
            await db.Orders.Where(o => o.Id == saleId).ExecuteUpdateAsync(s => s.SetProperty(o => o.CustomerId, receiver.CustomerId));
        if (print) await EnqueuePrintAsync(saleId, issued.Id, user);
        return Map(issued, billing.Cuit, await NamesAsync([issued.UserId]));
    }

    /// Anula una factura con una nota de crédito por el total.
    public async Task<InvoiceDto> CreditNoteAsync(int company, int branch, int user, int invoiceId, string reason)
    {
        reason = reason.Trim();
        if (reason.Length < 3) throw new InvoiceException("Indicá el motivo de la nota de crédito.");
        var invoice = await db.Invoices.AsNoTracking().SingleOrDefaultAsync(x => x.Id == invoiceId && x.CompanyId == company && x.BranchId == branch)
            ?? throw new InvoiceException("Comprobante no encontrado.", 404);
        if (!AfipCodes.IsInvoice(invoice.Type) || invoice.Status != "Autorizado")
            throw new InvoiceException("Solo se anulan facturas autorizadas.", 409);
        if (invoice.CreditNoteId.HasValue) throw new InvoiceException("La factura ya tiene nota de crédito.", 409);
        var billing = await RequireBilling(company);
        if (billing.Environment != invoice.Environment)
            throw new InvoiceException("La factura es de otro ambiente de AFIP que el configurado actualmente.", 409);

        var draft = new Invoice
        {
            CompanyId = company, BranchId = branch, OrderId = invoice.OrderId, Environment = invoice.Environment,
            Type = AfipCodes.CreditNoteFor(invoice.Type), PointOfSale = invoice.PointOfSale, Concept = invoice.Concept,
            DocType = invoice.DocType, DocNumber = invoice.DocNumber, ReceiverName = invoice.ReceiverName,
            ReceiverVatCondition = invoice.ReceiverVatCondition, CustomerId = invoice.CustomerId,
            Total = invoice.Total, Net = invoice.Net, Vat = invoice.Vat, VatJson = invoice.VatJson,
            AssociatedInvoiceId = invoice.Id, UserId = user, Reason = reason,
        };
        var issued = await IssueAsync(company, billing, draft, invoice);
        await EnqueuePrintAsync(invoice.OrderId, issued.Id, user);
        return Map(issued, billing.Cuit, await NamesAsync([issued.UserId]));
    }

    /// Vuelve a imprimir un comprobante autorizado, marcado como reimpresión y registrado con el usuario.
    public async Task<object> ReprintAsync(int company, int branch, int user, int invoiceId)
    {
        var invoice = await db.Invoices.AsNoTracking().SingleOrDefaultAsync(x => x.Id == invoiceId && x.CompanyId == company && x.BranchId == branch)
            ?? throw new InvoiceException("Comprobante no encontrado.", 404);
        if (invoice.Status != "Autorizado") throw new InvoiceException("Solo se reimprimen comprobantes autorizados.", 409);
        await EnqueuePrintAsync(invoice.OrderId, invoice.Id, user, reprint: true);
        return new { queued = true };
    }

    /// Al cobrar sale un solo comprobante: la factura o el ticket de pago, nunca los dos.
    /// Sin facturación configurada, el ticket de pago sale enseguida. Con facturación lista, la
    /// automática imprime la factura; si es manual o AFIP falla, la caja decide (Facturar o No facturar).
    public async Task<InvoiceDto?> AfterCheckoutAsync(int company, int branch, int user, int saleId)
    {
        var (missing, billing) = await ReadinessAsync(company);
        if (missing != null)
        {
            await EnqueuePrintAsync(saleId, userId: user);
            return null;
        }
        if (billing!.InvoicingMode != "Automatico") return null;
        try { return await InvoiceSaleAsync(company, branch, user, saleId, new InvoiceRequest()); }
        catch (Exception e) when (e is InvoiceException or AfipException)
        {
            logger.LogWarning("No se pudo facturar automáticamente la venta {SaleId}: {Message}", saleId, e.Message);
            return null;
        }
    }

    public static bool EmitterIsResponsableInscripto(BillingSettings billing) =>
        AfipCodes.VatCondition(billing.TaxCondition) == AfipCodes.CondResponsableInscripto;

    /// Monotributo y exento emiten C. Un responsable inscripto emite A a inscriptos y monotributistas
    /// (condiciones admitidas por AFIP para la clase A, RG 5616) y B al resto.
    public static int InvoiceType(BillingSettings billing, int receiverVatCondition) =>
        !EmitterIsResponsableInscripto(billing) ? AfipCodes.FacturaC
        : receiverVatCondition is AfipCodes.CondResponsableInscripto or AfipCodes.CondMonotributo ? AfipCodes.FacturaA : AfipCodes.FacturaB;

    private static bool Discriminates(int type) => AfipCodes.Letter(type) != "C";

    /// Reparte el total cobrado (con descuentos y recargos) entre las alícuotas de los productos,
    /// en proporción a sus subtotales, y separa neto e IVA de cada una.
    public static (decimal Net, decimal Vat, List<InvoiceVat> Detail) SplitVat(decimal total, IEnumerable<(decimal Subtotal, decimal Rate)> lines, bool discriminate)
    {
        if (total <= 0) throw new InvoiceException("No se puede facturar una venta sin importe.", 409);
        if (!discriminate) return (total, 0, []);
        var groups = lines.GroupBy(l => l.Rate).Select(g => (Rate: g.Key, Weight: g.Sum(l => l.Subtotal)))
            .Where(g => g.Weight > 0).OrderBy(g => g.Weight).ToList();
        var weight = groups.Sum(g => g.Weight);
        if (weight <= 0) throw new InvoiceException("La venta no tiene productos con importe para facturar.", 409);
        var detail = new List<InvoiceVat>();
        var assigned = 0m;
        for (var i = 0; i < groups.Count; i++)
        {
            // El grupo de mayor peso absorbe la diferencia de redondeo.
            var gross = i == groups.Count - 1 ? total - assigned : Round(total * groups[i].Weight / weight);
            assigned += gross;
            var baseAmount = Round(gross / (1 + groups[i].Rate / 100));
            detail.Add(new InvoiceVat(AfipCodes.VatId(groups[i].Rate), groups[i].Rate, baseAmount, gross - baseAmount));
        }
        detail = detail.OrderBy(d => d.Id).ToList();
        return (detail.Sum(d => d.BaseAmount), detail.Sum(d => d.Amount), detail);
    }

    public static string? QrUrl(Invoice x, string cuit)
    {
        if (x.Status != "Autorizado" || x.Cae == null || !long.TryParse(cuit, out var issuer)) return null;
        var payload = JsonSerializer.Serialize(new
        {
            ver = 1, fecha = x.Date.ToString("yyyy-MM-dd"), cuit = issuer, ptoVta = x.PointOfSale, tipoCmp = x.Type,
            nroCmp = x.Number, importe = x.Total, moneda = "PES", ctz = 1, tipoDocRec = x.DocType, nroDocRec = x.DocNumber,
            tipoCodAut = "E", codAut = long.Parse(x.Cae),
        });
        return "https://www.afip.gob.ar/fe/qr/?p=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(payload));
    }

    public static string Format(Invoice x) => $"{x.PointOfSale:00000}-{x.Number:00000000}";

    // ─── Emisión ──────────────────────────────────────────────────────────
    private async Task<Invoice> IssueAsync(int company, BillingSettings billing, Invoice draft, Invoice? associated)
    {
        var auth = await credentials.AuthAsync(company, billing.Environment, billing.Cuit);

        // Un solo emisor a la vez por punto de venta y tipo, durante toda la consulta a AFIP.
        await using var lockConnection = new NpgsqlConnection(db.Database.GetConnectionString());
        await lockConnection.OpenAsync();
        await using var lockTx = await lockConnection.BeginTransactionAsync();
        await using (var cmd = new NpgsqlCommand("SELECT pg_advisory_xact_lock(@a, @b)", lockConnection, lockTx))
        {
            cmd.Parameters.AddWithValue("a", company);
            cmd.Parameters.AddWithValue("b", draft.PointOfSale * 1000 + draft.Type * 2 + (billing.Environment == "Produccion" ? 1 : 0));
            await cmd.ExecuteNonQueryAsync();
        }

        // Intentos anteriores sin respuesta: se confirman o descartan antes de numerar.
        var pending = await db.Invoices.Where(x => x.CompanyId == company && x.Environment == draft.Environment
            && x.PointOfSale == draft.PointOfSale && x.Type == draft.Type && x.Status == "Procesando").ToListAsync();
        foreach (var row in pending) await ReconcileAsync(row, auth);
        var sameSale = pending.FirstOrDefault(x => x.Status == "Autorizado" && x.OrderId == draft.OrderId && x.AssociatedInvoiceId == draft.AssociatedInvoiceId);
        if (sameSale != null) return sameSale;

        var last = await afip.LastAuthorizedAsync(billing.Environment, auth, draft.PointOfSale, draft.Type);
        draft.Number = last + 1;
        draft.Date = DateOnly.FromDateTime(AfipClient.ArgentinaNow());
        draft.Status = "Procesando";
        draft.CreatedAt = DateTime.UtcNow;
        db.Invoices.Add(draft);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: "23505" })
        { throw new InvoiceException("La venta ya tiene una factura en curso. Actualizá la pantalla.", 409); }

        var detail = JsonSerializer.Deserialize<List<InvoiceVat>>(draft.VatJson, Json) ?? [];
        AfipInvoiceResult result;
        try
        {
            result = await afip.AuthorizeAsync(billing.Environment, auth, new AfipInvoiceRequest(
                draft.PointOfSale, draft.Type, draft.Number, draft.Concept, draft.DocType, draft.DocNumber, draft.Date,
                draft.Total, draft.Net, draft.Vat, draft.ReceiverVatCondition, detail,
                associated == null ? null : (associated.Type, associated.PointOfSale, associated.Number, long.Parse(billing.Cuit), associated.Date)));
        }
        catch (AfipException e) when (e.Transient)
        {
            // Queda "Procesando": el próximo intento consulta a AFIP si llegó a autorizarse.
            draft.Messages = e.Message; await db.SaveChangesAsync();
            throw new InvoiceException("AFIP no respondió. El comprobante quedó pendiente de verificación: reintentá en unos minutos.", 503);
        }
        catch (AfipException e)
        {
            draft.Status = "Rechazado"; draft.Messages = e.Message; await db.SaveChangesAsync();
            throw new InvoiceException(e.Message, 422);
        }

        draft.Messages = AfipClient.Describe(result.Messages);
        if (!result.Approved)
        {
            draft.Status = "Rechazado"; await db.SaveChangesAsync();
            throw new InvoiceException($"AFIP rechazó el comprobante. {draft.Messages}", 422);
        }
        await AuthorizedAsync(draft, result.Cae!, result.CaeExpiresAt);
        await lockTx.CommitAsync();
        return draft;
    }

    private async Task ReconcileAsync(Invoice row, AfipAuth auth)
    {
        var found = await afip.FindAsync(row.Environment, auth, row.PointOfSale, row.Type, row.Number);
        if (found != null && found.Total == row.Total && found.DocNumber == row.DocNumber)
        {
            row.Messages = "Confirmado en AFIP después de un corte de comunicación.";
            await AuthorizedAsync(row, found.Cae, found.CaeExpiresAt);
            return;
        }
        row.Status = "Rechazado";
        row.Messages = found == null
            ? "AFIP no registró el comprobante; se emitió de nuevo con otro número."
            : $"El número {Format(row)} corresponde a otro comprobante en AFIP.";
        await db.SaveChangesAsync();
    }

    private async Task AuthorizedAsync(Invoice row, string cae, DateOnly? expires)
    {
        row.Status = "Autorizado"; row.Cae = cae; row.CaeExpiresAt = expires; row.AuthorizedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        if (row.AssociatedInvoiceId is { } invoiceId)
            await db.Invoices.Where(x => x.Id == invoiceId).ExecuteUpdateAsync(s => s.SetProperty(x => x.CreditNoteId, row.Id));
    }

    // ─── Receptor y validaciones ─────────────────────────────────────────
    private record Receiver(int DocType, long DocNumber, string Name, int VatCondition, int? CustomerId);

    private async Task<Receiver> ReceiverAsync(int company, Order sale, InvoiceRequest request)
    {
        var customerId = request.CustomerId ?? (string.IsNullOrWhiteSpace(request.DocumentNumber) ? sale.CustomerId : null);
        if (customerId.HasValue)
        {
            var customer = await db.Customers.AsNoTracking().SingleOrDefaultAsync(c => c.Id == customerId && c.CompanyId == company)
                ?? throw new InvoiceException("Cliente no encontrado.", 404);
            var condition = AfipCodes.VatCondition(customer.VatCondition);
            var docType = AfipCodes.DocType(customer.DocumentType);
            if (docType == AfipCodes.DocSinIdentificar)
                return condition == AfipCodes.CondConsumidorFinal
                    ? new Receiver(docType, 0, customer.Name, condition, customer.Id)
                    : throw new InvoiceException($"El cliente {customer.Name} necesita CUIT para facturarle como {customer.VatCondition}.");
            return new Receiver(docType, Document(docType, customer.DocumentNumber), customer.Name, condition, customer.Id);
        }
        if (!string.IsNullOrWhiteSpace(request.DocumentNumber))
        {
            var docType = AfipCodes.DocType(request.DocumentType ?? "DNI");
            return new Receiver(docType, Document(docType, request.DocumentNumber), request.Name?.Trim() ?? "", AfipCodes.CondConsumidorFinal, null);
        }
        return new Receiver(AfipCodes.DocSinIdentificar, 0, "Consumidor final", AfipCodes.CondConsumidorFinal, null);
    }

    private static long Document(int docType, string? value)
    {
        var digits = new string((value ?? "").Where(char.IsDigit).ToArray());
        if (digits.Length == 0 || !long.TryParse(digits, out var number) || number <= 0)
            throw new InvoiceException("Falta el número de documento del cliente.");
        if (docType is AfipCodes.DocCuit or AfipCodes.DocCuil && !ValidCuit(digits))
            throw new InvoiceException($"El {(docType == AfipCodes.DocCuit ? "CUIT" : "CUIL")} {digits} no es válido.");
        return number;
    }

    public static bool ValidCuit(string digits)
    {
        if (digits.Length != 11 || !digits.All(char.IsDigit)) return false;
        int[] weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
        var sum = weights.Select((w, i) => w * (digits[i] - '0')).Sum();
        var check = 11 - sum % 11;
        check = check == 11 ? 0 : check == 10 ? 9 : check;
        return check == digits[10] - '0';
    }

    private async Task<BillingSettings> RequireBilling(int company)
    {
        var billing = await credentials.BillingAsync(company);
        if (!ValidCuit(billing.Cuit)) throw new InvoiceException("El CUIT de la empresa no es válido. Revisalo en Configuración › Empresa y facturación.", 409);
        if (billing.PointOfSale is null) throw new InvoiceException("Falta el punto de venta electrónico en Configuración › Empresa y facturación.", 409);
        if (string.IsNullOrWhiteSpace(billing.TaxCondition)) throw new InvoiceException("Falta la condición frente al IVA de la empresa.", 409);
        return billing;
    }

    private async Task<Order> RequireSale(int company, int branch, int saleId) =>
        await db.Orders.AsNoTracking().SingleOrDefaultAsync(o => o.Id == saleId && o.IdEmpresa == company && o.IdSucursal == branch)
        ?? throw new InvoiceException("Venta no encontrada.", 404);

    /// Monto desde el que AFIP exige identificar al consumidor final. Configurable porque cambia por resolución.
    private decimal IdentificationThreshold() =>
        configuration.GetValue<decimal?>("Afip:UmbralIdentificacionConsumidorFinal") ?? 10_000_000m;

    private async Task EnqueuePrintAsync(int saleId, int? invoiceId = null, int? userId = null, bool reprint = false)
    {
        db.PrintJobs.Add(new PrintJob
        {
            OrderId = saleId, PrinterId = configuration["PrinterSettings:QueueName"] ?? "Printer_POS_80C",
            CreatedAt = DateTime.UtcNow, Status = "Pendiente", JobType = "TicketVenta",
            InvoiceId = invoiceId, UserId = userId, Reprint = reprint,
        });
        await db.SaveChangesAsync();
    }

    private async Task<string> CuitAsync(int company)
    {
        try { return (await credentials.BillingAsync(company)).Cuit; }
        catch (InvoiceException) { return ""; } // Sin datos fiscales todavía: no hay QR que armar.
    }

    private async Task<Dictionary<int, string>> NamesAsync(IEnumerable<int> ids)
    {
        var list = ids.Where(id => id > 0).Distinct().ToList();
        return await db.Usuarios.AsNoTracking().Where(u => list.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => (u.Nombre + " " + u.Apellido).Trim());
    }

    private static InvoiceDto Map(Invoice x, string cuit, IReadOnlyDictionary<int, string> names) => new(x.Id, x.OrderId, x.Environment, x.Type, AfipCodes.TypeName(x.Type),
        x.PointOfSale, x.Number, Format(x), x.Date, x.DocType, x.DocNumber, x.ReceiverName, x.ReceiverVatCondition,
        x.Total, x.Net, x.Vat, JsonSerializer.Deserialize<List<InvoiceVat>>(x.VatJson, Json) ?? [], x.Status, x.Cae, x.CaeExpiresAt,
        x.Messages, x.AssociatedInvoiceId, x.CreditNoteId, x.CreatedAt, QrUrl(x, cuit),
        x.AuthorizedAt, x.UserId, names.GetValueOrDefault(x.UserId, ""), x.Reason);

    private static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
    private static string Money(decimal value) => "$ " + value.ToString("N2", System.Globalization.CultureInfo.GetCultureInfo("es-AR"));
}
