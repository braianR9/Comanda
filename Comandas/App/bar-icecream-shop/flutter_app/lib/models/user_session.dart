import 'empresa.dart';
import 'sucursal.dart';

class Rol {
  final int id;
  final String nombre;

  const Rol({required this.id, required this.nombre});

  factory Rol.fromJson(Map<String, dynamic> json) => Rol(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
      );
}

class UserSession {
  final String token;
  final int id;
  final String nombre;
  final String apellido;
  final String email;
  final int idRol;
  final int idEmpresa;
  final int idSucursal;
  final Empresa empresa;
  final Sucursal sucursal;
  final Rol rol;

  /// Restricción de salón para empleados; null = ve todos los sectores.
  final int? idSectorAsignado;
  final List<int> mesasExcluidasIds;

  const UserSession({
    this.token = '',
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.idRol,
    required this.idEmpresa,
    required this.idSucursal,
    required this.empresa,
    required this.sucursal,
    required this.rol,
    this.idSectorAsignado,
    this.mesasExcluidasIds = const [],
  });

  String get nombreCompleto => '$nombre $apellido';
  bool get isAdmin => rol.nombre == 'ADMIN';
  bool get isEncargado => rol.nombre == 'ENCARGADO';
  bool get isEmpleado => rol.nombre == 'EMPLEADO';

  /// Ventas, sectores/maestros y catálogos ("configuraciones").
  bool get canAccessMasters => isAdmin || isEncargado;

  /// Alta, edición y roles de usuarios: solo administradores.
  bool get canManageUsers => isAdmin;

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        token: json['token'] as String? ?? '',
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        apellido: json['apellido'] as String,
        email: json['email'] as String,
        idRol: json['idRol'] as int,
        idEmpresa: json['idEmpresa'] as int,
        idSucursal: json['idSucursal'] as int,
        empresa: Empresa.fromJson(json['empresa'] as Map<String, dynamic>),
        sucursal: Sucursal.fromJson(json['sucursal'] as Map<String, dynamic>),
        rol: Rol.fromJson(json['rol'] as Map<String, dynamic>),
        idSectorAsignado: (json['idSectorAsignado'] as num?)?.toInt(),
        mesasExcluidasIds: (json['mesasExcluidasIds'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'id': id,
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'idRol': idRol,
        'idEmpresa': idEmpresa,
        'idSucursal': idSucursal,
        'empresa': empresa.toJson(),
        'sucursal': sucursal.toJson(),
        'rol': {'id': rol.id, 'nombre': rol.nombre},
        'idSectorAsignado': idSectorAsignado,
        'mesasExcluidasIds': mesasExcluidasIds,
      };
}
