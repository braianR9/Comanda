class RestaurantTable {
  final int id;
  final int number;
  final String name;
  final String description;
  final int sectorId;
  final String status;
  final String shape;
  final String type;
  final int capacity;
  final bool active;
  final double positionX;
  final double positionY;

  const RestaurantTable({
    required this.id,
    required this.number,
    this.name = '',
    this.description = '',
    required this.sectorId,
    this.status = 'Libre',
    this.shape = 'Circular',
    this.type = '',
    this.capacity = 4,
    this.active = true,
    this.positionX = .44,
    this.positionY = .42,
  });

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: (json['id'] as num?)?.toInt() ?? 0,
        number: (json['number'] as num?)?.toInt() ??
            int.tryParse((json['name']?.toString() ?? '')
                .replaceAll(RegExp(r'[^0-9]'), '')) ??
            0,
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        sectorId: (json['sectorId'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? 'Libre',
        shape: json['shape']?.toString() ?? 'Circular',
        type: json['type']?.toString() ?? '',
        capacity: (json['capacity'] as num?)?.toInt() ?? 4,
        active: json['active'] as bool? ?? true,
        positionX: (json['positionX'] as num?)?.toDouble() ?? .44,
        positionY: (json['positionY'] as num?)?.toDouble() ?? .42,
      );
}
