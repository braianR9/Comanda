class CajaMedioPago {
  final String medioPago;
  final double total;

  const CajaMedioPago({required this.medioPago, required this.total});

  factory CajaMedioPago.fromJson(Map<String, dynamic> json) => CajaMedioPago(
        medioPago: json['medioPago']?.toString() ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

class CajaMovimiento {
  final int id;
  final String tipo;
  final double monto;
  final String motivo;
  final String usuario;
  final DateTime fecha;

  const CajaMovimiento({
    required this.id,
    required this.tipo,
    required this.monto,
    required this.motivo,
    required this.usuario,
    required this.fecha,
  });

  bool get isIngreso => tipo == 'Ingreso';

  factory CajaMovimiento.fromJson(Map<String, dynamic> json) => CajaMovimiento(
        id: (json['id'] as num?)?.toInt() ?? 0,
        tipo: json['tipo']?.toString() ?? '',
        monto: (json['monto'] as num?)?.toDouble() ?? 0,
        motivo: json['motivo']?.toString() ?? '',
        usuario: json['usuario']?.toString() ?? '',
        fecha: DateTime.parse(json['fecha'].toString()).toLocal(),
      );
}

class Caja {
  final int id;
  final String estado;
  final String usuarioApertura;
  final DateTime fechaApertura;
  final double montoInicial;
  final String? usuarioCierre;
  final DateTime? fechaCierre;
  final double? totalVentas;
  final double? totalIngresos;
  final double? totalEgresos;
  final double? totalEfectivoEsperado;
  final String? observaciones;
  final List<CajaMedioPago> detalle;
  final List<CajaMovimiento> movimientos;

  const Caja({
    required this.id,
    required this.estado,
    required this.usuarioApertura,
    required this.fechaApertura,
    required this.montoInicial,
    this.usuarioCierre,
    this.fechaCierre,
    this.totalVentas,
    this.totalIngresos,
    this.totalEgresos,
    this.totalEfectivoEsperado,
    this.observaciones,
    this.detalle = const [],
    this.movimientos = const [],
  });

  bool get abierta => estado == 'Abierta';

  factory Caja.fromJson(Map<String, dynamic> json) => Caja(
        id: (json['id'] as num?)?.toInt() ?? 0,
        estado: json['estado']?.toString() ?? 'Abierta',
        usuarioApertura: json['usuarioApertura']?.toString() ?? '',
        fechaApertura:
            DateTime.parse(json['fechaApertura'].toString()).toLocal(),
        montoInicial: (json['montoInicial'] as num?)?.toDouble() ?? 0,
        usuarioCierre: json['usuarioCierre']?.toString(),
        fechaCierre: json['fechaCierre'] == null
            ? null
            : DateTime.parse(json['fechaCierre'].toString()).toLocal(),
        totalVentas: (json['totalVentas'] as num?)?.toDouble(),
        totalIngresos: (json['totalIngresos'] as num?)?.toDouble(),
        totalEgresos: (json['totalEgresos'] as num?)?.toDouble(),
        totalEfectivoEsperado:
            (json['totalEfectivoEsperado'] as num?)?.toDouble(),
        observaciones: json['observaciones']?.toString(),
        detalle: (json['detalle'] as List<dynamic>? ?? const [])
            .map((e) => CajaMedioPago.fromJson(e as Map<String, dynamic>))
            .toList(),
        movimientos: (json['movimientos'] as List<dynamic>? ?? const [])
            .map((e) => CajaMovimiento.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
