import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_session.dart';

/// Color de marca de la sucursal y sus variantes. Todas se derivan de un solo
/// color base, así cualquier color elegido mantiene el contraste de textos y fondos.
class Brand {
  Brand._();

  /// El lila original del sistema.
  static const defaultColor = Color(0xFF6C5CE7);

  static Color _base = defaultColor;
  static Color get base => _base;

  static Color _shade(double lightness, {double? saturation}) {
    final hsl = HSLColor.fromColor(_base);
    return hsl
        .withLightness(lightness)
        .withSaturation(saturation ?? hsl.saturation)
        .toColor();
  }

  /// Oscurece el tono hasta lograr el contraste mínimo sobre [background]
  /// (los amarillos y verdes se ven más claros que un azul a igual luminosidad).
  static Color _readable(Color color, Color background, double ratio) {
    var hsl = HSLColor.fromColor(color);
    double contrast(Color c) {
      final a = c.computeLuminance(), b = background.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    while (contrast(hsl.toColor()) < ratio && hsl.lightness > 0.05) {
      hsl = hsl.withLightness(hsl.lightness - 0.02);
    }
    return hsl.toColor();
  }

  static double get _s => HSLColor.fromColor(_base).saturation;
  static double get _l => HSLColor.fromColor(_base).lightness;

  /// Color principal: botones, barra lateral, íconos destacados.
  static Color get primary => _base;

  /// Bordes y estados presionados del color principal.
  static Color get primaryDark =>
      _shade((_l - 0.08).clamp(0.0, 1.0).toDouble());

  /// Texto destacado sobre fondo claro (menús, etiquetas activas).
  static Color get strong =>
      _readable(_shade(0.36, saturation: _s * 0.5), tint, 4.6);

  /// Títulos y texto principal con un toque del color de marca.
  static Color get ink =>
      _readable(_shade(0.25, saturation: _s * 0.47), Colors.white, 7.5);

  /// Texto secundario.
  static Color get subtle =>
      _readable(_shade(0.47, saturation: _s * 0.15), Colors.white, 4.6);

  /// Texto o íconos atenuados.
  static Color get muted => _shade(0.68, saturation: _s * 0.38);

  /// Fondo de elementos seleccionados.
  static Color get tint => _shade(0.96, saturation: 1);

  /// Fondos y bordes suaves.
  static Color get surface => _shade(0.93, saturation: _s * 0.4);

  /// Texto legible sobre el color principal: blanco o casi negro, el que más contraste.
  static Color get onPrimary {
    const dark = Color(0xFF1F1F24);
    final l = _base.computeLuminance();
    final onWhite = 1.05 / (l + 0.05);
    final onDark = (l + 0.05) / (dark.computeLuminance() + 0.05);
    return onWhite >= onDark ? Colors.white : dark;
  }

  /// Un color muy claro hace difícil leer el texto blanco de la barra lateral.
  static bool isTooLight(Color color) =>
      1.05 / (color.computeLuminance() + 0.05) < 3;

  static void _set(Color color) => _base = color;
}

/// Colores sugeridos en la paleta. Todos admiten texto blanco encima (contraste ≥ 3,9:1),
/// porque la barra lateral y los botones usan texto blanco.
const brandPresets = <(String, Color)>[
  ('Lila', Brand.defaultColor),
  ('Violeta', Color(0xFF8E44AD)),
  ('Azul', Color(0xFF2F6FDE)),
  ('Celeste', Color(0xFF0A7FB3)),
  ('Turquesa', Color(0xFF0B8577)),
  ('Verde', Color(0xFF23824A)),
  ('Oliva', Color(0xFF6B7A22)),
  ('Mostaza', Color(0xFFA87700)),
  ('Naranja', Color(0xFFCC5A0E)),
  ('Rojo', Color(0xFFD63B3B)),
  ('Frambuesa', Color(0xFFD12E6E)),
  ('Rosa', Color(0xFFC9407F)),
  ('Café', Color(0xFF8B5E3C)),
  ('Grafito', Color(0xFF4A5160)),
];

/// Guarda y aplica el color de la sucursal en el almacenamiento local del
/// navegador (localStorage en la web), con una clave por empresa y sucursal.
class BrandProvider extends ChangeNotifier {
  static const _lastKey = 'brand_color_last';
  String? _key;

  Color get color => Brand.base;
  bool get isDefault => Brand.base == Brand.defaultColor;

  static String _keyFor(UserSession s) =>
      'brand_color_e${s.idEmpresa}_s${s.idSucursal}';

  /// Antes del login usa el último color, para que la pantalla no cambie de golpe.
  Future<void> restoreLast() async {
    final value = await _read(_lastKey);
    if (value != null) _apply(value);
  }

  /// Al iniciar o cambiar de sesión, aplica el color guardado para esa sucursal.
  Future<void> useSession(UserSession? session) async {
    final key = session == null ? null : _keyFor(session);
    if (key == _key) return;
    _key = key;
    if (key == null) return;
    final value = await _read(key);
    if (key != _key) return; // Cambió la sesión mientras se leía.
    _apply(value ?? Brand.defaultColor);
    await _write(_lastKey, Brand.base);
  }

  Future<void> save(Color color) async {
    _apply(color);
    if (_key != null) await _write(_key!, color);
    await _write(_lastKey, color);
  }

  Future<void> reset() => save(Brand.defaultColor);

  void _apply(Color color) {
    if (color == Brand.base) return;
    Brand._set(color);
    notifyListeners();
    // Muchas pantallas leen Brand directamente: se reconstruye todo el árbol
    // sin perder el estado (pantalla abierta, formularios, mesas).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
    });
  }

  static Future<Color?> _read(String key) async {
    try {
      final value = (await SharedPreferences.getInstance()).getInt(key);
      return value == null ? null : Color(value);
    } catch (_) {
      return null; // Almacenamiento bloqueado: se usa el color por defecto.
    }
  }

  static Future<void> _write(String key, Color color) async {
    try {
      await (await SharedPreferences.getInstance())
          .setInt(key, color.toARGB32());
    } catch (_) {}
  }
}

/// Convierte "#RRGGBB" o "RRGGBB" en un color; null si no es válido.
Color? parseHexColor(String text) {
  final hex = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}

String toHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
