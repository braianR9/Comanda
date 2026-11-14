using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using BarIceCreamShop.Api.Models;
using BarIceCreamShop.Api.Services;

namespace BarIceCreamShop.Api.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly AuthService _authService;

        public AuthController(AuthService authService)
        {
            _authService = authService;
        }

        /// <summary>Login con email y password</summary>
        [HttpPost("login")]
        public async Task<ActionResult<ApiResponse<LoginResponseDto>>> Login([FromBody] LoginRequestDto dto)
        {
            try
            {
                var result = await _authService.LoginAsync(dto);

                if (result == null)
                    return Unauthorized(ApiResponse<LoginResponseDto>.Fail("Credenciales invalidas.", 401));

                return Ok(ApiResponse<LoginResponseDto>.Ok(result));
            }
            catch (Exception ex)
            {
                return StatusCode(500, ApiResponse<LoginResponseDto>.ServerError(ex.Message));
            }
        }

        /// <summary>Renueva el token de una sesión vigente (la app lo pide mientras hay actividad).</summary>
        [Authorize, HttpPost("renovar")]
        public async Task<IActionResult> Renew()
        {
            if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
                return Unauthorized(ApiResponse<object>.Fail("La sesión venció. Volvé a iniciar sesión.", 401));
            var token = await _authService.RenewAsync(userId);
            return token == null
                ? Unauthorized(ApiResponse<object>.Fail("La sesión venció. Volvé a iniciar sesión.", 401))
                : Ok(ApiResponse<object>.Ok(new { token }));
        }
    }
}
