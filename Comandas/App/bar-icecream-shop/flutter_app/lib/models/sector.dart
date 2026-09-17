class Sector {
  final int id;
  final String name;
  final String description;
  final int order;
  final bool active;

  const Sector({
    required this.id,
    required this.name,
    this.description = '',
    this.order = 0,
    this.active = true,
  });

  factory Sector.fromJson(Map<String, dynamic> json) => Sector(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
      );

  Sector copyWith({
    int? id,
    String? name,
    String? description,
    int? order,
    bool? active,
  }) =>
      Sector(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        order: order ?? this.order,
        active: active ?? this.active,
      );
}
