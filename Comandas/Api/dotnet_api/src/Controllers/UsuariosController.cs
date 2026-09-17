using System.Security.Claims;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BarIceCreamShop.Api.Controllers;

public class UsuarioStatusRequest
{
    public bool Activo { get; set; }
}

[ApiController]
[Authorize]
[Route("api/usuarios")]
public class UsuariosController(UsuarioService service) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<UsuarioDto>>>> List(string? search, bool includeInactive = false)
    {
        RequireAdmin();
        return Ok(ApiResponse<List<UsuarioDto>>.Ok(await service.List(Company, search, includeInactive)));
    }

    [HttpGet("roles")]
    public async Task<ActionResult<ApiResponse<List<RolDto>>>> Roles()
    {
        RequireAdmin();
        return Ok(ApiResponse<List<RolDto>>.Ok(await service.ListRoles()));
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ApiResponse<UsuarioDto>>> Get(int id)
    {
        RequireAdmin();
        var user = await service.Get(Company, id);
        return user == null
            ? NotFound(ApiResponse<UsuarioDto>.NotFound("Usuario no encontrado."))
            : Ok(ApiResponse<UsuarioDto>.Ok(user));
    }

    [HttpPost]
    public async Task<ActionResult<ApiResponse<UsuarioDto>>> Create(UsuarioRequest request) =>
        await Run(() =>
        {
            RequireAdmin();
            return service.Create(Company, Branch, request);
        }, 201);

    [HttpPut("{id:int}")]
    public async Task<ActionResult<ApiResponse<UsuarioDto>>> Update(int id, UsuarioRequest request) =>
        await Run(() =>
        {
            RequireAdmin();
            return service.Update(Company, id, request);
        });

    [HttpPatch("{id:int}/status")]
    public async Task<ActionResult<ApiResponse<UsuarioDto>>> Status(int id, UsuarioStatusRequest request) =>
        await Run(() =>
        {
            RequireAdmin();
            return service.SetActive(Company, id, request.Activo, CurrentUserId);
        });

    private int Company => int.TryParse(User.FindFirstValue("id_empresa"), out var id)
        ? id : throw new SaleException("Token inválido.", 401);

    private int Branch => int.TryParse(User.FindFirstValue("id_sucursal"), out var id)
        ? id : throw new SaleException("Token inválido.", 401);

    private int CurrentUserId => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)
        ? id : throw new SaleException("Token inválido.", 401);

    private void RequireAdmin()
    {
        if (User.FindFirstValue("rol_nombre") != "ADMIN")
            throw new SaleException("No tenés permisos para administrar usuarios.", 403);
    }

    private async Task<ActionResult<ApiResponse<T>>> Run<T>(Func<Task<T>> action, int code = 200)
    {
        try
        {
            var result = await action();
            return StatusCode(code, ApiResponse<T>.Ok(result, code));
        }
        catch (SaleException e)
        {
            return StatusCode(e.StatusCode, ApiResponse<T>.Fail(e.Message, e.StatusCode));
        }
    }
}
