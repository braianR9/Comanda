/// Token vigente de la sesión del local.
///
/// La sesión se renueva mientras se usa, así que el token cambia. Muchas
/// pantallas y providers guardan el token que recibieron al abrirse: al armar
/// cada pedido usan [use], que devuelve siempre el vigente.
class SessionToken {
  SessionToken._();

  static String? current;

  /// Token a enviar: el vigente si hay sesión; si no, el que tenía guardado quien llama.
  static String use(String stored) {
    final value = current;
    return value != null && value.isNotEmpty && stored.isNotEmpty
        ? value
        : stored;
  }
}
