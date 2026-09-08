using Microsoft.AspNetCore.Mvc;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;

namespace BarIceCreamShop.Api.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PrinterController : ControllerBase
    {
        private readonly PrinterService _printerService;

        public PrinterController(PrinterService printerService)
        {
            _printerService = printerService;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<IEnumerable<PrintJob>>>> GetPrintJobs()
        {
            try
            {
                var printJobs = await _printerService.GetAllPrintersAsync();
                return Ok(ApiResponse<IEnumerable<PrintJob>>.Ok(printJobs));
            }
            catch (Exception ex)
            {
                return StatusCode(500, ApiResponse<IEnumerable<PrintJob>>.ServerError(ex.Message));
            }
        }

        [HttpPost]
        public async Task<ActionResult<ApiResponse<PrintJob>>> CreatePrintJob([FromBody] PrintJob printJob)
        {
            try
            {
                if (printJob == null)
                    return BadRequest(ApiResponse<PrintJob>.Fail("Los datos son requeridos."));
                var created = await _printerService.CreatePrinterAsync(printJob);
                return StatusCode(201, ApiResponse<PrintJob>.Ok(created, 201));
            }
            catch (Exception ex)
            {
                return StatusCode(500, ApiResponse<PrintJob>.ServerError(ex.Message));
            }
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult<ApiResponse<object>>> DeletePrintJob(int id)
        {
            try
            {
                var result = await _printerService.DeletePrinterAsync(id);
                if (!result)
                    return NotFound(ApiResponse<object>.NotFound());
                return Ok(ApiResponse<object>.Ok(null!));
            }
            catch (Exception ex)
            {
                return StatusCode(500, ApiResponse<object>.ServerError(ex.Message));
            }
        }
    }
}
