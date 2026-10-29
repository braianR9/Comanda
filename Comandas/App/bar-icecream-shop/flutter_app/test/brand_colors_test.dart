import 'package:focobr/models/user_session.dart';
import 'package:focobr/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserSession _session(int branch) => UserSession.fromJson({
      'id': 1,
      'nombre': 'Test',
      'apellido': '',
      'email': '',
      'idRol': 1,
      'idEmpresa': 1,
      'idSucursal': branch,
      'empresa': {
        'id': 1,
        'nombre': '',
        'cuit': '',
        'email': '',
        'telefono': '',
        'activa': true
      },
      'sucursal': {
        'id': branch,
        'idEmpresa': 1,
        'nombre': 'Sucursal $branch',
        'direccion': '',
        'telefono': '',
        'activa': true
      },
      'rol': {'id': 1, 'nombre': 'ADMIN'},
    });

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Distancia por canal (0-255) entre dos colores.
int _distance(Color a, Color b) => [
      ((a.r - b.r) * 255).abs(),
      ((a.g - b.g) * 255).abs(),
      ((a.b - b.b) * 255).abs(),
    ].reduce((x, y) => x > y ? x : y).round();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el lila por defecto conserva los tonos originales', () async {
    SharedPreferences.setMockInitialValues({});
    await BrandProvider().reset();
    expect(Brand.primary, const Color(0xFF6C5CE7));
    expect(_distance(Brand.ink, const Color(0xFF2D2260)), lessThan(24));
    expect(_distance(Brand.strong, const Color(0xFF3D2D8A)), lessThan(32));
    expect(_distance(Brand.tint, const Color(0xFFEDE9FF)), lessThan(16));
  });

  test('con cualquier color de la paleta los textos se leen', () async {
    SharedPreferences.setMockInitialValues({});
    final brand = BrandProvider();
    for (final (name, color) in brandPresets) {
      await brand.save(color);
      expect(_contrast(Brand.ink, Colors.white), greaterThan(7), reason: name);
      expect(_contrast(Brand.strong, Brand.tint), greaterThan(4.5),
          reason: name);
      expect(_contrast(Brand.subtle, Colors.white), greaterThan(4.5),
          reason: name);
      expect(_contrast(Brand.onPrimary, Brand.primary), greaterThan(3),
          reason: name);
      expect(_contrast(Colors.white, Brand.primary), greaterThan(3.9),
          reason: '$name admite texto blanco en la barra lateral');
      expect(Brand.isTooLight(color), isFalse, reason: name);
    }
  });

  test('cada sucursal guarda su color en el almacenamiento local', () async {
    SharedPreferences.setMockInitialValues({});
    final brand = BrandProvider();
    await brand.useSession(_session(1));
    await brand.save(const Color(0xFF2E9E5B));
    await brand.useSession(_session(2));
    expect(Brand.primary, Brand.defaultColor,
        reason: 'sucursal 2 sin color propio');
    await brand.save(const Color(0xFFD63B3B));
    await brand.useSession(_session(1));
    expect(Brand.primary, const Color(0xFF2E9E5B));

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getInt('brand_color_e1_s1'), const Color(0xFF2E9E5B).toARGB32());
    expect(
        prefs.getInt('brand_color_e1_s2'), const Color(0xFFD63B3B).toARGB32());

    // Antes del login se usa el último color de la sucursal que se usó.
    await brand.useSession(null);
    final fresh = BrandProvider();
    await fresh.restoreLast();
    expect(Brand.primary, const Color(0xFF2E9E5B));
  });

  test('códigos hexadecimales', () {
    expect(parseHexColor('#2f6fde'), const Color(0xFF2F6FDE));
    expect(parseHexColor('2F6FDE'), const Color(0xFF2F6FDE));
    expect(parseHexColor('#12345'), isNull);
    expect(toHex(const Color(0xFF0FA3D9)), '#0FA3D9');
    expect(Brand.isTooLight(const Color(0xFFFFE066)), isTrue);
  });
}
