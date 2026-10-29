using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace BarIceCreamShop.Api.Middleware;

public sealed class SystemErrorMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, SystemEventSink sink)
    {
        try
        {
            await next(context);
            if (context.Response.StatusCode >= 500 && !context.Items.ContainsKey("system_error_logged"))
                sink.Error("HTTP", "El servidor devolvió un error HTTP.", status: context.Response.StatusCode);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
        catch (SaleException e) when (!context.Response.HasStarted)
        {
            context.Response.Clear();
            context.Response.StatusCode = e.StatusCode;
            await context.Response.WriteAsJsonAsync(ApiResponse<object>.Fail(e.Message, e.StatusCode));
        }
        catch (Exception e)
        {
            sink.Error("API", "Error inesperado al procesar la solicitud.", e, 500);
            if (context.Response.HasStarted) throw;
            context.Response.Clear();
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(ApiResponse<object>.ServerError(
                $"Ocurrió un error en el servidor. Referencia: {context.TraceIdentifier}"));
        }
    }
}

// También registra y oculta los detalles de los 500 que los controladores ya capturan.
public sealed class SystemErrorResultFilter(SystemEventSink sink) : IAsyncResultFilter
{
    public async Task OnResultExecutionAsync(ResultExecutingContext context, ResultExecutionDelegate next)
    {
        if (context.Result is ObjectResult result && result.StatusCode >= 500)
        {
            var message = result.Value?.GetType().GetProperty("Error")?.GetValue(result.Value)?.ToString();
            sink.Error("Controller", message ?? "Error del servidor.", status: result.StatusCode);
            context.HttpContext.Items["system_error_logged"] = true;
            result.Value = ApiResponse<object>.ServerError($"Ocurrió un error en el servidor. Referencia: {context.HttpContext.TraceIdentifier}");
        }
        await next();
    }
}
