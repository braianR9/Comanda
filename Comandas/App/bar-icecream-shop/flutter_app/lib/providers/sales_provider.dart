import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/product.dart';

typedef SalePaymentInput = ({int cardId, double baseAmount, double amount});

typedef SaleLine = ({Product product, int quantity, String? comment});

class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'La sesión venció. Volvé a iniciar sesión.';
}

class SaleCatalogItem {
  final int id;
  final String name;
  final String type;
  final double value;
  const SaleCatalogItem(this.id, this.name, {this.type = '', this.value = 0});
}

class SaleItemSnapshot {
  final int id;
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String? comment;
  const SaleItemSnapshot(
      {required this.id,
      required this.productId,
      required this.name,
      required this.unitPrice,
      required this.quantity,
      this.comment});
}

class SaleSnapshot {
  final int id;
  final int number;
  final int version;
  final Map<String, int> itemIds;
  final int tableId;
  final String status;
  final List<SaleItemSnapshot> items;
  final List<int> joinedTableIds;
  final DateTime? openedAt;
  final double total;
  final double paidAmount;
  final int paymentCount;
  final double paymentAdjustment;
  final SaleCatalogItem? discount;

  const SaleSnapshot(
      {required this.id,
      required this.number,
      required this.version,
      required this.itemIds,
      required this.tableId,
      required this.status,
      required this.items,
      required this.joinedTableIds,
      required this.openedAt,
      this.total = 0,
      this.paidAmount = 0,
      this.paymentCount = 0,
      this.paymentAdjustment = 0,
      this.discount});

  factory SaleSnapshot.fromJson(Map<String, dynamic> json) => SaleSnapshot(
        id: (json['id'] as num).toInt(),
        number: (json['number'] as num?)?.toInt() ?? 0,
        version: (json['version'] as num?)?.toInt() ?? 0,
        tableId: (json['tableId'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        paymentCount: (json['payments'] as List? ?? const []).length,
        paymentAdjustment: (json['paymentAdjustment'] as num?)?.toDouble() ?? 0,
        paidAmount: (json['payments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .fold<double>(
                0,
                (sum, payment) =>
                    sum + ((payment['amount'] as num?)?.toDouble() ?? 0)),
        discount: json['discount'] is Map<String, dynamic>
            ? SaleCatalogItem(
                (json['discount']['id'] as num?)?.toInt() ?? 0,
                json['discount']['name']?.toString() ?? '',
                type: json['discount']['type']?.toString() ?? '',
                value: (json['discount']['value'] as num?)?.toDouble() ?? 0,
              )
            : null,
        openedAt:
            DateTime.tryParse(json['openedAt']?.toString() ?? '')?.toLocal(),
        items: [
          for (final item in (json['items'] as List? ?? const []))
            if (item is Map<String, dynamic>)
              SaleItemSnapshot(
                id: (item['id'] as num).toInt(),
                productId: (item['productId'] as num).toInt(),
                name: item['name']?.toString() ?? '',
                unitPrice: (item['unitPrice'] as num?)?.toDouble() ?? 0,
                quantity: (item['quantity'] as num?)?.toInt() ?? 0,
                comment: item['comment']?.toString(),
              ),
        ],
        joinedTableIds: [
          for (final id in (json['joinedTableIds'] as List? ?? const []))
            (id as num).toInt(),
        ],
        itemIds: {
          for (final item in (json['items'] as List? ?? const []))
            if (item is Map<String, dynamic>)
              '${(item['productId'] as num).toInt()}':
                  (item['id'] as num).toInt(),
        },
      );
}

class CommandSnapshot {
  final int id;
  final int number;
  const CommandSnapshot(this.id, this.number);
}

class SalesProvider extends ChangeNotifier {
  String _token = '';

  void configure({required String token, required int userId}) =>
      _token = token;

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<SaleSnapshot> createSale({
    required int tableId,
    required List<SaleLine> lines,
    int? waiterId,
  }) async {
    final response = await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/sales'),
            headers: _headers,
            body: jsonEncode({
              'tableId': tableId,
              'waiterId': waiterId,
              'items': [for (final line in lines) _linePayload(line)],
            }))
        .timeout(ApiConfig.timeout);
    return _sale(response);
  }

  Future<SaleSnapshot> synchronizeItems({
    required int saleId,
    required int version,
    required Map<String, int> existingItemIds,
    required List<SaleLine> lines,
    void Function(SaleSnapshot)? onProgress,
  }) async {
    var currentVersion = version;
    var ids = Map<String, int>.from(existingItemIds);
    SaleSnapshot? snapshot;
    final currentProducts = {for (final line in lines) line.product.id};
    final removedItems = existingItemIds.entries
        .where((entry) => !currentProducts.contains(entry.key)).toList();
    for (final line in lines) {
      final itemId = ids[line.product.id];
      snapshot = itemId == null
          ? await _addItem(saleId, line)
          : await _updateItem(saleId, itemId, line, currentVersion);
      onProgress?.call(snapshot);
      currentVersion = snapshot.version;
      ids = snapshot.itemIds;
    }
    // Save replacements before removing previous items so a product change
    // never temporarily empties an already sent order.
    for (final entry in removedItems) {
      snapshot = await _deleteItem(saleId, entry.value, currentVersion);
      onProgress?.call(snapshot);
      currentVersion = snapshot.version;
    }
    return snapshot ?? await getSale(saleId);
  }

  Future<CommandSnapshot> sendCommand(int saleId, int version) async {
    final response = await http
        .post(
          Uri.parse(
              '${ApiConfig.baseUrl}/api/sales/$saleId/send-command?version=$version'),
          headers: _headers,
        )
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>;
    return CommandSnapshot(
      (data['id'] as num?)?.toInt() ?? 0,
      (data['number'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> enqueueCommandPrint({
    required int saleId,
  }) async {
    final printersResponse = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/printers'), headers: _headers)
        .timeout(ApiConfig.timeout);
    final values = _body(printersResponse)['data'] as List? ?? const [];
    final printers = values.whereType<Map<String, dynamic>>().where((item) {
      final usage = item['usage']?.toString().toLowerCase() ?? '';
      return item['active'] != false &&
          (usage.isEmpty ||
              usage == 'ambos' ||
              usage.contains('comanda') ||
              usage.contains('command') ||
              usage.contains('pedido') ||
              usage.contains('kitchen'));
    }).toList();
    if (printers.isEmpty) {
      throw Exception('No hay una impresora activa configurada para comandas.');
    }
    final printer =
        printers.where((item) => item['isDefault'] == true).firstOrNull ??
            printers.first;
    _body(await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/Printer'),
          headers: _headers,
          body: jsonEncode({
            'orderId': saleId,
            'printerId': printer['queueName']?.toString(),
            'printerConfigurationId': (printer['id'] as num).toInt(),
            'jobType': 'Command',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'Pending',
          }),
        )
        .timeout(ApiConfig.timeout));
  }

  Future<SaleSnapshot> getSale(int saleId) async => _sale(await http
      .get(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId'),
        headers: _headers,
      )
      .timeout(ApiConfig.timeout));

  Future<List<SaleSnapshot>> getActiveSales() async {
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/sales/active'),
            headers: _headers)
        .timeout(ApiConfig.timeout);
    final values = _body(response)['data'] as List? ?? const [];
    return [
      for (final value in values)
        if (value is Map<String, dynamic>) SaleSnapshot.fromJson(value),
    ];
  }

  Future<SaleSnapshot> applyDiscount(int saleId, int version,
          {int? discountId,
          required String name,
          required String type,
          required double value}) async =>
      _sale(await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId/discount'),
              headers: _headers,
              body: jsonEncode({
                'discountId': discountId,
                'name': name,
                'type': type,
                'value': value,
                'version': version
              }))
          .timeout(ApiConfig.timeout));

  Future<SaleSnapshot> addPayments(
          int saleId, int version, List<SalePaymentInput> payments) async =>
      _sale(await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId/payments'),
              headers: _headers,
              body: jsonEncode({
                'payments': [
                  for (final payment in payments)
                    {
                      'cardId': payment.cardId,
                      'baseAmount': payment.baseAmount,
                      'amount': payment.amount
                    }
                ],
                'version': version
              }))
          .timeout(ApiConfig.timeout));

  Future<SaleSnapshot> checkout(int saleId, int version) =>
      _postAction('/api/sales/$saleId/checkout?version=$version');
  Future<SaleSnapshot> cancel(int saleId, int version) =>
      _postAction('/api/sales/$saleId/cancel?version=$version');

  Future<SaleSnapshot> moveTable(int saleId, int tableId, int version) =>
      _tableAction(saleId, 'move-table', tableId, version);
  Future<SaleSnapshot> joinTable(int saleId, int tableId, int version) =>
      _tableAction(saleId, 'join-table', tableId, version);

  Future<SaleSnapshot> _postAction(String endpoint) async => _sale(await http
      .post(Uri.parse('${ApiConfig.baseUrl}$endpoint'), headers: _headers)
      .timeout(ApiConfig.timeout));

  Future<SaleSnapshot> _tableAction(
          int saleId, String action, int tableId, int version) async =>
      _sale(await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId/$action'),
              headers: _headers,
              body: jsonEncode({'tableId': tableId, 'version': version}))
          .timeout(ApiConfig.timeout));

  Future<List<SaleCatalogItem>> paymentTypes() =>
      _catalog('/api/sales-catalogs/cards');
  Future<List<SaleCatalogItem>> discounts() =>
      _catalog('/api/sales-catalogs/discounts');

  Future<List<SaleCatalogItem>> _catalog(String endpoint) async {
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}$endpoint'), headers: _headers)
        .timeout(ApiConfig.timeout);
    final raw = _body(response)['data'];
    final values = raw is List
        ? raw
        : raw is Map<String, dynamic> && raw['items'] is List
            ? raw['items'] as List
            : const [];
    return [
      for (final value in values)
        if (value is Map<String, dynamic>)
          SaleCatalogItem(
            (value['id'] as num).toInt(),
            value['name']?.toString() ??
                value['nombre']?.toString() ??
                'Sin nombre',
            type: value['adjustmentType']?.toString() ??
                value['type']?.toString() ??
                value['tipo']?.toString() ??
                '',
            value: (value['percentage'] as num?)?.toDouble() ??
                (value['value'] as num?)?.toDouble() ??
                (value['valor'] as num?)?.toDouble() ??
                0,
          ),
    ];
  }

  Future<SaleSnapshot> _addItem(int saleId, SaleLine line) async => _sale(
      await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId/items'),
              headers: _headers, body: jsonEncode(_linePayload(line)))
          .timeout(ApiConfig.timeout));

  Future<SaleSnapshot> _updateItem(
          int saleId, int itemId, SaleLine line, int version) async =>
      _sale(await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/sales/$saleId/items/$itemId'),
            headers: _headers,
            body: jsonEncode({
              'quantity': line.quantity,
              'comment': _comment(line.comment),
              'version': version
            }),
          )
          .timeout(ApiConfig.timeout));

  Future<SaleSnapshot> _deleteItem(int saleId, int itemId, int version) async =>
      _sale(await http
          .delete(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/sales/$saleId/items/$itemId?version=$version'),
            headers: _headers,
          )
          .timeout(ApiConfig.timeout));

  Map<String, dynamic> _linePayload(SaleLine line) => {
        'productId': int.parse(line.product.id),
        'quantity': line.quantity,
        'comment': _comment(line.comment),
      };

  String? _comment(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  SaleSnapshot _sale(http.Response response) =>
      SaleSnapshot.fromJson(_body(response)['data'] as Map<String, dynamic>);

  Map<String, dynamic> _body(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) throw const UnauthorizedException();
      throw Exception(decoded['error']?.toString() ??
          decoded['title']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return decoded;
  }
}
