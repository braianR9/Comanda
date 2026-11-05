namespace BarIceCreamShop.Api.Middleware
{
    public class ApiKeyMiddleware
    {
        private readonly RequestDelegate _next;

        public ApiKeyMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context, IConfiguration configuration)
        {
            // Swagger y el agente de impresión (se autentica con su propia clave) no usan la API Key.
            if (context.Request.Path.StartsWithSegments("/swagger") || context.Request.Path.StartsWithSegments("/api/print-agent"))
            {
                await _next(context);
                return;
            }

            var headerName = configuration["ApiKey:HeaderName"] ?? "focoKey";
            if (!context.Request.Headers.TryGetValue(headerName, out var extractedApiKey))
            {
                context.Response.StatusCode = 401;
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsJsonAsync(new
                {
                    Codigo = 401,
                    Data = (object?)null,
                    Error = $"API Key requerida. Incluí el header '{headerName}'."
                });
                return;
            }

            var apiKey = configuration["ApiKey:Value"];
            if (string.IsNullOrEmpty(apiKey) || !apiKey.Equals(extractedApiKey))
            {
                context.Response.StatusCode = 403;
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsJsonAsync(new
                {
                    Codigo = 403,
                    Data = (object?)null,
                    Error = "API Key inválida."
                });
                return;
            }

            await _next(context);
        }
    }
}
