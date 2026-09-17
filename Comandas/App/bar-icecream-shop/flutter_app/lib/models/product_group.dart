class ProductGroup {
  final String id;
  final String name;
  final String description;
  final String observationType;
  final String? parentId;
  final String? imageBase64;
  final String? imageUrl;
  final bool applyProducts;
  final bool applyIngredients;
  final bool applyDelivery;
  final bool applySalon;
  final bool showDigitalMenu;

  const ProductGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.observationType = '',
    this.parentId,
    this.imageBase64,
    this.imageUrl,
    this.applyProducts = true,
    this.applyIngredients = false,
    this.applyDelivery = true,
    this.applySalon = true,
    this.showDigitalMenu = true,
  });

  bool get isSubgroup => parentId != null;

  factory ProductGroup.fromJson(Map<String, dynamic> json) => ProductGroup(
        id: json['id'].toString(),
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        observationType: json['observationType'] as String? ?? '',
        parentId: json['parentId'] as String?,
        imageBase64: json['imageBase64'] as String?,
        imageUrl: json['imageUrl'] as String?,
        applyProducts: json['applyProducts'] as bool? ?? true,
        applyIngredients: json['applyIngredients'] as bool? ?? false,
        applyDelivery: json['applyDelivery'] as bool? ?? true,
        applySalon: json['applySalon'] as bool? ?? true,
        showDigitalMenu: json['showDigitalMenu'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'observationType': observationType,
        'parentId': parentId,
        'imageBase64': imageBase64,
        'imageUrl': imageUrl,
        'applyProducts': applyProducts,
        'applyIngredients': applyIngredients,
        'applyDelivery': applyDelivery,
        'applySalon': applySalon,
        'showDigitalMenu': showDigitalMenu,
      };
}
