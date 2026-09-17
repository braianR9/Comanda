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
    }
}
