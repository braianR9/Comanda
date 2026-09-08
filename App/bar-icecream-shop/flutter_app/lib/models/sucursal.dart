class Sucursal {
  final int id;
  final int idEmpresa;
  final String nombre;
  final String direccion;
  final String telefono;
  final bool activa;

  const Sucursal({
    required this.id,
    required this.idEmpresa,
    required this.nombre,
    required this.direccion,
    required this.telefono,
    required this.activa,
  });

  factory Sucursal.fromJson(Map<String, dynamic> json) => Sucursal(
        id: json['id'] as int,
        idEmpresa: json['idEmpresa'] as int,
        nombre: json['nombre'] as String,
        direccion: json['direccion'] as String,
        telefono: json['telefono'] as String,
        activa: json['activa'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'idEmpresa': idEmpresa,
        'nombre': nombre,
        'direccion': direccion,
        'telefono': telefono,
        'activa': activa,
      };
}
