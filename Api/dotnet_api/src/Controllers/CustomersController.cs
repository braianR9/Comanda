using System.Security.Claims;using BarIceCreamShop.Api.Models;using BarIceCreamShop.Api.Services;using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;
namespace BarIceCreamShop.Api.Controllers;
[ApiController,Authorize,Route("api/customers")]public class CustomersController(CustomerService service):ControllerBase{
 [HttpGet]public async Task<ActionResult<ApiResponse<List<CustomerDto>>>>List(string?search,bool includeInactive=false)=>Ok(ApiResponse<List<CustomerDto>>.Ok(await service.List(Company,search,includeInactive)));
 [HttpGet("{id:int}")]public async Task<ActionResult<ApiResponse<CustomerDto>>>Get(int id){var x=await service.Get(Company,id);return x==null?NotFound(ApiResponse<CustomerDto>.NotFound("Cliente no encontrado.")):Ok(ApiResponse<CustomerDto>.Ok(x));}
 [HttpPost]public async Task<ActionResult<ApiResponse<CustomerDto>>>Create(CustomerRequest r)=>await Run(()=>service.Create(Company,r),201);
 [HttpPut("{id:int}")]public async Task<ActionResult<ApiResponse<CustomerDto>>>Update(int id,CustomerRequest r)=>await Run(()=>service.Update(Company,id,r));
 [HttpPatch("{id:int}/status")]public async Task<ActionResult<ApiResponse<CustomerDto>>>Status(int id,PrinterStatusRequest r)=>await Run(()=>service.Status(Company,id,r.Active));
 [HttpDelete("{id:int}")]public async Task<ActionResult<ApiResponse<CustomerDto>>>Delete(int id)=>await Run(()=>service.Status(Company,id,false));
 private int Company=>int.TryParse(User.FindFirstValue("id_empresa"),out var id)?id:throw new SaleException("Token inválido.",401);private async Task<ActionResult<ApiResponse<T>>>Run<T>(Func<Task<T>>a,int code=200){try{var x=await a();return StatusCode(code,ApiResponse<T>.Ok(x,code));}catch(SaleException e){return StatusCode(e.StatusCode,ApiResponse<T>.Fail(e.Message,e.StatusCode));}}}
