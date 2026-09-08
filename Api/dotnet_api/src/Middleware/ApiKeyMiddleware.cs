namespace BarIceCreamShop.Api.Middleware
{
    public class ApiKeyMiddleware
    {
        private readonly RequestDelegate _next;
        private const string ApiKeyHeaderName = "focoKey";

        public ApiKeyMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context, IConfiguration configuration)
        {
            // Permitir acceso a Swagger sin API Key
            if (context.Request.Path.StartsWithSegments("/swagger"))
            {
                await _next(context);
                return;
            }

            if (!context.Request.Headers.TryGetValue(ApiKeyHeaderName, out var extractedApiKey))
            {
                context.Response.StatusCode = 401;
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsJsonAsync(new
                {
                    Codigo = 401,
                    Data = (object?)null,
                    Error = "API Key requerida. Incluye el header 'X-Api-Key'."
                });
                return;
            }

            var apiKey = configuration["ApiKey:Value"];
            if (!apiKey!.Equals(extractedApiKey))
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
