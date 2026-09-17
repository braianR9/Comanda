import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class StockMovement {
  final int id;
  final DateTime date;
  final int productId;
  final String productName;
  final String type;
  final double quantity;
  final double previousStock;
  final double newStock;
  final String source;
  final String note;
  final String userName;

  /// Número de pedido impreso en la comanda/ticket (no el interno de la venta).
  final int? saleNumber;

  const StockMovement(
      {required this.id,
      required this.date,
      required this.productId,
      required this.productName,
      required this.type,
      required this.quantity,
      required this.previousStock,
      required this.newStock,
      required this.source,
      required this.note,
      required this.userName,
      this.saleNumber});

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
      id: (json['id'] as num).toInt(),
      date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      productId: (json['productId'] as num?)?.toInt() ?? 0,
      productName: json['productName']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      previousStock: (json['previousStock'] as num?)?.toDouble() ?? 0,
      newStock: (json['newStock'] as num?)?.toDouble() ?? 0,
      source: json['source']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      saleNumber: (json['saleNumber'] as num?)?.toInt());
}

class StockMovementProvider extends ChangeNotifier {
  String _token = '';
  bool loading = false;
  String? error;
  List<StockMovement> movements = [];

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token'
      };

  Future<void> load(String token,
      {int? productId,
      String? type,
      int? saleNumber,
      DateTime? dateFrom,
      DateTime? dateTo}) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/stock-movements')
          .replace(queryParameters: {
        if (productId != null) 'productId': '$productId',
        if (type != null && type.isNotEmpty) 'type': type,
        if (dateFrom != null) 'from': _apiDate(dateFrom),
        if (dateTo != null) 'to': _apiDate(dateTo, endOfDay: true),
      });
      final data = _body(await http
              .get(uri, headers: _headers)
              .timeout(ApiConfig.timeout))['data'] as List? ??
          const [];
      movements = [
        for (final item in data)
          StockMovement.fromJson(item as Map<String, dynamic>)
      ];
      if (saleNumber != null) {
        movements = movements
            .where((movement) => movement.saleNumber == saleNumber)
            .toList();
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _apiDate(DateTime date, {bool endOfDay = false}) => DateTime(
        date.year,
        date.month,
        date.day,
        endOfDay ? 23 : 0,
        endOfDay ? 59 : 0,
        endOfDay ? 59 : 0,
        endOfDay ? 999 : 0,
      ).toUtc().toIso8601String();

  Future<void> add(
      {required int productId,
      required String type,
      required double quantity,
      String? note}) async {
    _body(await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/stock-movements'),
            headers: _headers,
            body: jsonEncode({
              'productId': productId,
              'type': type,
              'quantity': quantity,
              'note': note?.trim().isEmpty == true ? null : note?.trim()
            }))
        .timeout(ApiConfig.timeout));
    await load(_token);
  }

  Map<String, dynamic> _body(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          body['detail']?.toString() ??
          body['title']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
