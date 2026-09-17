import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class DiscountCatalog {
  final int id;
  final String name;
  final String description;
  final String type;
  final double value;
  final bool active;
  final DateTime? validFrom;
  final DateTime? validUntil;
  const DiscountCatalog(
      {this.id = 0,
      required this.name,
      this.description = '',
      required this.type,
      required this.value,
      this.active = true,
      this.validFrom,
      this.validUntil});

  factory DiscountCatalog.fromJson(Map<String, dynamic> json) =>
      DiscountCatalog(
          id: (json['id'] as num).toInt(),
          name: json['name']?.toString() ?? '',
          description: json['description']?.toString() ?? '',
          type: json['type']?.toString() ?? 'Porcentaje',
          value: (json['value'] as num?)?.toDouble() ?? 0,
          active: json['active'] as bool? ?? true,
          validFrom: DateTime.tryParse(json['validFrom']?.toString() ?? ''),
          validUntil: DateTime.tryParse(json['validUntil']?.toString() ?? ''));

  Map<String, dynamic> toRequest() => {
        'name': name,
        'description': description.trim().isEmpty ? null : description.trim(),
        'type': type,
        'value': value,
        'validFrom': validFrom?.toUtc().toIso8601String(),
        'validUntil': validUntil?.toUtc().toIso8601String()
      };
}

class CardCatalog {
  final int id;
  final String name;
  final String description;
  final String adjustmentType;
  final double percentage;
  final bool active;
  const CardCatalog(
      {this.id = 0,
      required this.name,
      this.description = '',
      required this.adjustmentType,
      required this.percentage,
      this.active = true});

  factory CardCatalog.fromJson(Map<String, dynamic> json) => CardCatalog(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      adjustmentType: json['adjustmentType']?.toString() ?? 'Sin ajuste',
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
      active: json['active'] as bool? ?? true);

  Map<String, dynamic> toRequest() => {
        'name': name,
        'description': description.trim().isEmpty ? null : description.trim(),
        'adjustmentType': adjustmentType,
        'percentage': percentage
      };
}

class SalesCatalogsProvider extends ChangeNotifier {
  String _token = '';
  bool loading = false;
  String? error;
  List<DiscountCatalog> discounts = [];
  List<CardCatalog> cards = [];

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token'
      };

  Future<void> load(String token) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        _get('/api/sales-catalogs/discounts?includeInactive=true'),
        _get('/api/sales-catalogs/cards?includeInactive=true'),
      ]);
      discounts = [
        for (final value in values[0]) DiscountCatalog.fromJson(value)
      ];
      cards = [for (final value in values[1]) CardCatalog.fromJson(value)];
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> saveDiscount(DiscountCatalog value) async {
    await _save('/api/sales-catalogs/discounts', value.id, value.toRequest());
    await load(_token);
  }

  Future<void> saveCard(CardCatalog value) async {
    await _save('/api/sales-catalogs/cards', value.id, value.toRequest());
    await load(_token);
  }

  Future<void> setDiscountActive(DiscountCatalog value, bool active) async {
    await _status('/api/sales-catalogs/discounts/${value.id}/status', active);
    await load(_token);
  }

  Future<void> setCardActive(CardCatalog value, bool active) async {
    await _status('/api/sales-catalogs/cards/${value.id}/status', active);
    await load(_token);
  }

  Future<List<Map<String, dynamic>>> _get(String path) async {
    final data = _body(await http
            .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: _headers)
            .timeout(ApiConfig.timeout))['data'] as List? ??
        [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> _save(String path, int id, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path${id == 0 ? '' : '/$id'}');
    final response = id == 0
        ? await http.post(uri, headers: _headers, body: jsonEncode(body))
        : await http.put(uri, headers: _headers, body: jsonEncode(body));
    _body(response);
  }

  Future<void> _status(String path, bool active) async => _body(await http
      .patch(Uri.parse('${ApiConfig.baseUrl}$path'),
          headers: _headers, body: jsonEncode({'active': active}))
      .timeout(ApiConfig.timeout));

  Map<String, dynamic> _body(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
