class ProductComponent {
  final int productId;
  final String name;
  final double quantity;
  const ProductComponent(
      {required this.productId, required this.name, required this.quantity});
  factory ProductComponent.fromJson(Map<String, dynamic> json) =>
      ProductComponent(
          productId: (json['productId'] as num).toInt(),
          name: json['name'] as String? ?? '',
          quantity: (json['quantity'] as num).toDouble());
  Map<String, dynamic> toJson() =>
      {'productId': productId, 'name': name, 'quantity': quantity};
}
