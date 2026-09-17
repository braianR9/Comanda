using System.ComponentModel.DataAnnotations.Schema;

namespace BarIceCreamShop.Api.Models
{
    /// Mesas quitadas manualmente de un sector asignado a un usuario (empleado).
    [Table("usuario_mesas_excluidas")]
    public class UsuarioMesaExcluida
    {
        [Column("id_usuario")]
        public int IdUsuario { get; set; }

        [Column("id_mesa")]
        public int IdMesa { get; set; }
    }
}
