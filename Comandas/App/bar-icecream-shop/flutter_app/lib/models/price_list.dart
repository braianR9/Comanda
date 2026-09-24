class PriceList {
  final int id;
  final String nombre;
  final bool esPredeterminada;
  final bool activa;
  final DateTime fechaCreacion;
  final DateTime fechaModificacion;
  final int cantidadPrecios;

  const PriceList({
    required this.id,
    required this.nombre,
    required this.esPredeterminada,
    required this.activa,
    required this.fechaCreacion,
    required this.fechaModificacion,
    this.cantidadPrecios = 0,
  });

  factory PriceList.fromJson(Map<String, dynamic> json) => PriceList(
        id: (json['id'] as num?)?.toInt() ?? 0,
        nombre: json['nombre']?.toString() ?? '',
        esPredeterminada: json['esPredeterminada'] as bool? ?? false,
        activa: json['activa'] as bool? ?? true,
        fechaCreacion:
            DateTime.parse(json['fechaCreacion'].toString()).toLocal(),
        fechaModificacion:
            DateTime.parse(json['fechaModificacion'].toString()).toLocal(),
        cantidadPrecios: (json['cantidadPrecios'] as num?)?.toInt() ?? 0,
      );
}

class ReferenciaSimple {
  final int id;
  final String nombre;
  const ReferenciaSimple({required this.id, required this.nombre});

  factory ReferenciaSimple.fromJson(Map<String, dynamic> json) =>
      ReferenciaSimple(
        id: (json['id'] as num?)?.toInt() ?? 0,
        nombre: json['nombre']?.toString() ?? '',
      );
}

class ProductPrice {
  final int idProducto;
  final int codigo;
  final String nombre;
  final ReferenciaSimple rubro;
  final ReferenciaSimple? subRubro;
  final double? precio;

  const ProductPrice({
    required this.idProducto,
    required this.codigo,
    required this.nombre,
    required this.rubro,
    this.subRubro,
    this.precio,
  });

  bool get tienePrecio => precio != null;

  ProductPrice copyWith({double? precio}) => ProductPrice(
        idProducto: idProducto,
        codigo: codigo,
        nombre: nombre,
        rubro: rubro,
        subRubro: subRubro,
        precio: precio ?? this.precio,
      );

  factory ProductPrice.fromJson(Map<String, dynamic> json) => ProductPrice(
        idProducto: (json['idProducto'] as num?)?.toInt() ?? 0,
        codigo: (json['codigo'] as num?)?.toInt() ?? 0,
        nombre: json['nombre']?.toString() ?? '',
        rubro: ReferenciaSimple.fromJson(json['rubro'] as Map<String, dynamic>),
        subRubro: json['subRubro'] == null
            ? null
            : ReferenciaSimple.fromJson(
                json['subRubro'] as Map<String, dynamic>),
        precio: (json['precio'] as num?)?.toDouble(),
      );
}

class BulkPricePreviewItem {
  final int idProducto;
  final String nombre;
  final double? precioActual;
  final double precioNuevo;

  const BulkPricePreviewItem({
    required this.idProducto,
    required this.nombre,
    required this.precioActual,
    required this.precioNuevo,
  });

  factory BulkPricePreviewItem.fromJson(Map<String, dynamic> json) =>
      BulkPricePreviewItem(
        idProducto: (json['idProducto'] as num?)?.toInt() ?? 0,
        nombre: json['nombre']?.toString() ?? '',
        precioActual: (json['precioActual'] as num?)?.toDouble(),
        precioNuevo: (json['precioNuevo'] as num?)?.toDouble() ?? 0,
      );
}
