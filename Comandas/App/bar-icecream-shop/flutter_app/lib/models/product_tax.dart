class ProductTax {
  final String id;
  final String name;
  final String description;
  final double percentage;

  const ProductTax({
    required this.id,
    required this.name,
    required this.description,
    required this.percentage,
  });

  factory ProductTax.fromJson(Map<String, dynamic> json) => ProductTax(
        id: json['id'].toString(),
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        percentage: (json['percentage'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'percentage': percentage,
      };
}
