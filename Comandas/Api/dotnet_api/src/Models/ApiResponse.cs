namespace BarIceCreamShop.Api.Models
{
    public class ApiResponse<T>
    {
        public int Codigo { get; set; }
        public T? Data { get; set; }
        public string? Error { get; set; }

        public static ApiResponse<T> Ok(T data, int codigo = 200) =>
            new() { Codigo = codigo, Data = data, Error = null };

        public static ApiResponse<T> Fail(string error, int codigo = 400) =>
            new() { Codigo = codigo, Data = default, Error = error };

        public static ApiResponse<T> NotFound(string error = "Recurso no encontrado") =>
            new() { Codigo = 404, Data = default, Error = error };

        public static ApiResponse<T> ServerError(string error = "Error interno del servidor") =>
            new() { Codigo = 500, Data = default, Error = error };
    }
}
