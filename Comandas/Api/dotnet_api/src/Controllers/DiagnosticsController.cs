using System.ComponentModel.DataAnnotations;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace BarIceCreamShop.Api.Controllers;

public record ClientErrorRequest([Required, MaxLength(4000)] string Message,
    [MaxLength(12000)] string? Stack, [MaxLength(150)] string? Library);

[ApiController, Authorize, Route("api/diagnostics")]
public sealed class DiagnosticsController(SystemEventSink sink) : ControllerBase
{
    [HttpPost("client-error"), EnableRateLimiting("client-errors")]
    public object ClientError(ClientErrorRequest request)
    {
        sink.Error("Flutter", request.Message + "\n" + request.Library + "\n" + request.Stack);
        return ApiResponse<object>.Ok(new { reference = HttpContext.TraceIdentifier });
    }
}
