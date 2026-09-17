class AppRole {
  final int id;
  final String name;
  const AppRole({required this.id, required this.name});

  factory AppRole.fromJson(Map<String, dynamic> json) => AppRole(
        id: (json['id'] as num).toInt(),
        name: json['nombre']?.toString() ?? '',
      );
}

class AppUser {
  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final int roleId;
  final String roleName;
  final int branchId;
  final String branchName;
  final bool active;

  /// Solo aplica al rol EMPLEADO; null = ve todos los sectores.
  final int? assignedSectorId;
  final List<int> excludedTableIds;

  const AppUser({
    this.id = 0,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.roleId,
    this.roleName = '',
    this.branchId = 0,
    this.branchName = '',
    this.active = true,
    this.assignedSectorId,
    this.excludedTableIds = const [],
  });

  String get fullName => '$firstName $lastName';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['nombre']?.toString() ?? '',
        lastName: json['apellido']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        roleId: (json['idRol'] as num?)?.toInt() ?? 0,
        roleName: json['rolNombre']?.toString() ?? '',
        branchId: (json['idSucursal'] as num?)?.toInt() ?? 0,
        branchName: json['sucursalNombre']?.toString() ?? '',
        active: json['activo'] as bool? ?? true,
        assignedSectorId: (json['idSectorAsignado'] as num?)?.toInt(),
        excludedTableIds: (json['mesasExcluidasIds'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson({String? password}) => {
        'nombre': firstName,
        'apellido': lastName,
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        'idRol': roleId,
        'activo': active,
        'idSectorAsignado': assignedSectorId,
        'mesasExcluidasIds': excludedTableIds,
      };
}
