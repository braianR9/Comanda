using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
namespace BarIceCreamShop.Api.Controllers;

[ApiController, Authorize(Policy = BarIceCreamShop.Api.Security.SalePermissions.CashierPolicy)]
public class InvoicesController(InvoiceService invoices, AfipCredentialService credentials) : ControllerBase
{
    private int Company => int.Parse(User.FindFirstValue("id_empresa")!);
    private int Branch => int.Parse(User.FindFirstValue("id_sucursal")!);
    private int Actor => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private bool Manager => User.FindFirstValue("rol_nombre") is "ADMIN" or "CAJA" or "ENCARGADO";
    private async Task<IActionResult> Run(Func<Task<object>> action, bool manager = false)
    {
        if (manager && !Manager) return StatusCode(403, ApiResponse<object>.Fail("Requiere ADMIN o CAJA.", 403));
        try { return Ok(ApiResponse<object>.Ok(await action())); }
        catch (InvoiceException e) { return StatusCode(e.StatusCode, ApiResponse<object>.Fail(e.Message, e.StatusCode)); }
        catch (AfipException e)
        {
            var code = e.Transient ? 503 : 422;
            return StatusCode(code, ApiResponse<object>.Fail(e.Message, code));
        }
    }

    [HttpGet("api/sales/{id:int}/comprobantes")]
    public Task<IActionResult> ForSale(int id) => Run(async () => await invoices.ForSaleAsync(Company, Branch, id));

    [HttpPost("api/sales/{id:int}/facturar")]
    public Task<IActionResult> Invoice(int id, InvoiceRequest request) => Run(async () => await invoices.InvoiceSaleAsync(Company, Branch, Actor, id, request));

    [HttpPost("api/comprobantes/{id:int}/nota-credito")]
    public Task<IActionResult> CreditNote(int id, CreditNoteRequest request) => Run(async () => await invoices.CreditNoteAsync(Company, Branch, Actor, id, request.Reason), true);

    [HttpGet("api/comprobantes")]
    public Task<IActionResult> List(int page = 1) => Run(() => invoices.ListAsync(Company, Branch, page));

    [HttpGet("api/facturacion/pendientes")]
    public Task<IActionResult> Pending(int page = 1) => Run(() => invoices.PendingAsync(Company, Branch, page));

    [HttpGet("api/facturacion/config")]
    public Task<IActionResult> Configuration() => Run(() => invoices.ConfigurationAsync(Company));

    [HttpPost("api/sales/{id:int}/ticket")]
    public Task<IActionResult> PaymentTicket(int id) => Run(() => invoices.PrintPaymentTicketAsync(Company, Branch, Actor, id));

    [HttpPost("api/comprobantes/{id:int}/reimprimir")]
    public Task<IActionResult> Reprint(int id) => Run(() => invoices.ReprintAsync(Company, Branch, Actor, id));

    [HttpGet("api/afip/certificado")]
    public Task<IActionResult> CertificateStatus() => Run(() => credentials.StatusAsync(Company), true);

    [HttpPost("api/afip/certificado/csr")]
    public Task<IActionResult> CertificateRequest(CertificateRequestInput input) => Run(() => credentials.CreateRequestAsync(Company, input), true);

    [HttpPut("api/afip/certificado")]
    public Task<IActionResult> UploadCertificate(CertificateUploadInput input) => Run(() => credentials.UploadCertificateAsync(Company, input), true);

    [HttpPost("api/afip/probar")]
    public Task<IActionResult> Test() => Run(() => credentials.TestAsync(Company), true);
}
