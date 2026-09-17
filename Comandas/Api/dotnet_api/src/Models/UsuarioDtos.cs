namespace BarIceCreamShop.Api.Models
{
    public class UsuarioDto
    {
        public int Id { get; set; }
        public string Nombre { get; set; } = string.Empty;
        public string Apellido { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public int IdRol { get; set; }
        public string RolNombre { get; set; } = string.Empty;
        public int IdSucursal { get; set; }
        public string SucursalNombre { get; set; } = string.Empty;
        public bool Activo { get; set; }

        /// null = el empleado ve todos los sectores.
        public int? IdSectorAsignado { get; set; }
        public string? SectorAsignadoNombre { get; set; }
        public List<int> MesasExcluidasIds { get; set; } = [];
    }

    public class UsuarioRequest
    {
        public string Nombre { get; set; } = string.Empty;
        public string Apellido { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;

        /// Requerida al crear; en edición, dejar vacío para no cambiarla.
        public string? Password { get; set; }
        public int IdRol { get; set; }
        public bool Activo { get; set; } = true;

        /// Solo aplica a empleados; null = ve todos los sectores.
        public int? IdSectorAsignado { get; set; }

        /// Mesas quitadas manualmente del sector asignado. Se ignora si IdSectorAsignado es null.
        public List<int> MesasExcluidasIds { get; set; } = [];
    }

    public class RolDto
    {
        public int Id { get; set; }
        public string Nombre { get; set; } = string.Empty;
    }
}
