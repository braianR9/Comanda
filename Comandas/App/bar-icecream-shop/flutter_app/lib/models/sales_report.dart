class SalesReportLine {
  final DateTime date;
  final int orderNumber;
  final int productCode;
  final String productName;
  final double quantity;
  final double total;
  final double realAmount;
  final String rubroName;
  final String? subRubroName;
  final String orderType;
  final String? sectorName;

  const SalesReportLine({
    required this.date,
    required this.orderNumber,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.total,
    required this.realAmount,
    required this.rubroName,
    this.subRubroName,
    required this.orderType,
    this.sectorName,
  });

  factory SalesReportLine.fromJson(Map<String, dynamic> json) =>
      SalesReportLine(
        date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        orderNumber: (json['orderNumber'] as num?)?.toInt() ?? 0,
        productCode: (json['productCode'] as num?)?.toInt() ?? 0,
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        realAmount: (json['realAmount'] as num?)?.toDouble() ?? 0,
        rubroName: json['rubroNombre']?.toString() ?? '',
        subRubroName: json['subRubroNombre']?.toString(),
        orderType: json['tipoPedido']?.toString() ?? '',
        sectorName: json['sectorNombre']?.toString(),
      );
}

class SalesReportResult {
  final List<SalesReportLine> items;
  final double totalQuantity;
  final double totalAmount;
  final double totalRealAmount;

  const SalesReportResult({
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    required this.totalRealAmount,
  });

  factory SalesReportResult.fromJson(Map<String, dynamic> json) =>
      SalesReportResult(
        items: (json['items'] as List? ?? const [])
            .map((item) =>
                SalesReportLine.fromJson(item as Map<String, dynamic>))
            .toList(),
        totalQuantity: (json['totalQuantity'] as num?)?.toDouble() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        totalRealAmount: (json['totalRealAmount'] as num?)?.toDouble() ?? 0,
      );

  static const empty = SalesReportResult(
      items: [], totalQuantity: 0, totalAmount: 0, totalRealAmount: 0);
}
