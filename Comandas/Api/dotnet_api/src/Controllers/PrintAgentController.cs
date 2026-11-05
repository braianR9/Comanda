using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

/// Lo usa el agente de impresión del local. Se autentica solo con su clave (header X-Agente-Clave).
[ApiController, AllowAnonymous, Route("api/print-agent")]
public sealed class PrintAgentController(PrintAgentService service) : ControllerBase
{
    [HttpPost("next")]
    public async Task<ActionResult<ApiResponse<PrintAgentJobDto?>>> Next(CancellationToken cancellationToken)
    {
        var agent = await Agent();
        if (agent == null) return Unauthorized(ApiResponse<PrintAgentJobDto?>.Fail("Clave del agente inválida.", 401));
        return Ok(ApiResponse<PrintAgentJobDto?>.Ok(await service.NextAsync(agent, cancellationToken)));
    }

    [HttpPost("jobs/{id:int}/result")]
    public async Task<ActionResult<ApiResponse<object>>> Result(int id, PrintAgentResultRequest request)
    {
        var agent = await Agent();
        if (agent == null) return Unauthorized(ApiResponse<object>.Fail("Clave del agente inválida.", 401));
        return await service.ResultAsync(agent, id, request)
            ? Ok(ApiResponse<object>.Ok(new { id }))
            : NotFound(ApiResponse<object>.NotFound("Trabajo no encontrado."));
    }

    private Task<PrintAgent?> Agent() =>
        service.AuthenticateAsync(Request.Headers["X-Agente-Clave"], Request.Headers["X-Agente-Equipo"]);
}
