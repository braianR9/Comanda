using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

public abstract class CatalogControllerBase : ControllerBase
{
    protected int CompanyId => int.TryParse(User.FindFirstValue("id_empresa"), out var id)
        ? id : throw new CatalogoException("El token no contiene una empresa válida.", 401);

    protected ActionResult<ApiResponse<T>> CatalogError<T>(CatalogoException ex) =>
        StatusCode(ex.StatusCode, ApiResponse<T>.Fail(ex.Message, ex.StatusCode));
}
