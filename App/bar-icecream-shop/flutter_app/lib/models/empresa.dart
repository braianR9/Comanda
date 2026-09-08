class Empresa {
  final int id;
  final String nombre;
  final String cuit;
  final String email;
  final String telefono;
  final String? imagenUrl;
  final bool activa;

  const Empresa({
    required this.id,
    required this.nombre,
    required this.cuit,
    required this.email,
    required this.telefono,
    this.imagenUrl,
    required this.activa,
  });

  factory Empresa.fromJson(Map<String, dynamic> json) => Empresa(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        cuit: json['cuit'] as String,
        email: json['email'] as String,
        telefono: json['telefono'] as String,
        imagenUrl: json['imagenUrl'] as String?,
        activa: json['activa'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'cuit': cuit,
        'email': email,
        'telefono': telefono,
        'imagenUrl': imagenUrl,
        'activa': activa,
      };
}
