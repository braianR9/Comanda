using System.Security.Claims;

namespace BarIceCreamShop.Api.Security;

public static class SalePermissions
{
    public const string CashierPolicy = "Cashier";
    public static string RoleName(string name) => name == "ENCARGADO" ? "CAJA" : name;
    public static bool CanCollect(ClaimsPrincipal user) =>
        user.Identity?.IsAuthenticated == true &&
        user.FindFirstValue("rol_nombre") is "ADMIN" or "CAJA" or "ENCARGADO";
}
