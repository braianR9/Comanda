class Product {
  final String id;
  final String name;
  final String category;
  final String subcategory;
  final double price;
  final bool active;
  final String? imageBase64;
  final String? imageUrl;
  final String code;
  final String description;
  final String type;
  final double cost;
  final double taxRate;
  final String taxId;
  final double minimumStock;
  final double idealStock;
  final bool stockAlarm;
  final bool minimumStockAlarm;
  final bool checkStockOnSale;
  final String stockUpdatesOn;
  final String quantityOperation;
  final double currentStock;
  final bool showDelivery;
  final bool showSalon;
  final bool showDigitalMenu;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory = '',
    required this.price,
    this.active = true,
    this.imageBase64,
    this.imageUrl,
    this.code = '',
    this.description = '',
    this.type = 'Producto simple',
    this.cost = 0,
    this.taxRate = 21,
    this.taxId = 'iva-21',
    this.minimumStock = 0,
    this.idealStock = 1,
    this.stockAlarm = false,
    this.minimumStockAlarm = false,
    this.checkStockOnSale = false,
    this.stockUpdatesOn = 'Producto',
    this.quantityOperation = 'Entero',
    this.currentStock = 0,
    this.showDelivery = true,
    this.showSalon = true,
    this.showDigitalMenu = true,
  });

  Product copyWith({
    String? name,
    String? category,
    String? subcategory,
    double? price,
    bool? active,
    String? imageBase64,
    String? imageUrl,
    String? code,
    String? description,
    String? type,
    double? cost,
    double? taxRate,
    String? taxId,
    double? minimumStock,
    double? idealStock,
    bool? stockAlarm,
    bool? minimumStockAlarm,
    bool? checkStockOnSale,
    String? stockUpdatesOn,
    String? quantityOperation,
    double? currentStock,
    bool? showDelivery,
    bool? showSalon,
    bool? showDigitalMenu,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        subcategory: subcategory ?? this.subcategory,
        price: price ?? this.price,
        active: active ?? this.active,
        imageBase64: imageBase64 ?? this.imageBase64,
        imageUrl: imageUrl ?? this.imageUrl,
        code: code ?? this.code,
        description: description ?? this.description,
        type: type ?? this.type,
        cost: cost ?? this.cost,
        taxRate: taxRate ?? this.taxRate,
        taxId: taxId ?? this.taxId,
        minimumStock: minimumStock ?? this.minimumStock,
        idealStock: idealStock ?? this.idealStock,
        stockAlarm: stockAlarm ?? this.stockAlarm,
        minimumStockAlarm: minimumStockAlarm ?? this.minimumStockAlarm,
        checkStockOnSale: checkStockOnSale ?? this.checkStockOnSale,
        stockUpdatesOn: stockUpdatesOn ?? this.stockUpdatesOn,
        quantityOperation: quantityOperation ?? this.quantityOperation,
        currentStock: currentStock ?? this.currentStock,
        showDelivery: showDelivery ?? this.showDelivery,
        showSalon: showSalon ?? this.showSalon,
        showDigitalMenu: showDigitalMenu ?? this.showDigitalMenu,
      );

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'].toString(),
        name: json['name'] as String,
        category: json['category'] as String,
        subcategory: json['subcategory'] as String? ?? '',
        price: (json['price'] as num).toDouble(),
        active: json['active'] as bool? ?? true,
        imageBase64: json['imageBase64'] as String?,
        imageUrl: json['imageUrl'] as String?,
        code: json['code'] as String? ?? '',
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'Producto simple',
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 21,
        taxId: json['taxId'] as String? ?? 'iva-21',
        minimumStock: (json['minimumStock'] as num?)?.toDouble() ?? 0,
        idealStock: (json['idealStock'] as num?)?.toDouble() ?? 1,
        stockAlarm: json['stockAlarm'] as bool? ?? false,
        minimumStockAlarm: json['minimumStockAlarm'] as bool? ?? false,
        checkStockOnSale: json['checkStockOnSale'] as bool? ?? false,
        stockUpdatesOn: json['stockUpdatesOn'] as String? ?? 'Producto',
        quantityOperation: json['quantityOperation'] as String? ?? 'Entero',
        currentStock: (json['currentStock'] as num?)?.toDouble() ?? 0,
        showDelivery: json['showDelivery'] as bool? ?? true,
        showSalon: json['showSalon'] as bool? ?? true,
        showDigitalMenu: json['showDigitalMenu'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'price': price,
        'active': active,
        'imageBase64': imageBase64,
        'imageUrl': imageUrl,
        'code': code,
        'description': description,
        'type': type,
        'cost': cost,
        'taxRate': taxRate,
        'taxId': taxId,
        'minimumStock': minimumStock,
        'idealStock': idealStock,
        'stockAlarm': stockAlarm,
        'minimumStockAlarm': minimumStockAlarm,
        'checkStockOnSale': checkStockOnSale,
        'stockUpdatesOn': stockUpdatesOn,
        'quantityOperation': quantityOperation,
        'currentStock': currentStock,
        'showDelivery': showDelivery,
        'showSalon': showSalon,
        'showDigitalMenu': showDigitalMenu,
      };
}
