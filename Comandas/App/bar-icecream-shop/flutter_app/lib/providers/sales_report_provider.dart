import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/sales_report.dart';

class SalesReportProvider extends ChangeNotifier {
  bool loading = false;
  String? error;
  SalesReportResult result = SalesReportResult.empty;
  String _token = '';

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(
    String token, {
    DateTime? from,
    DateTime? to,
    bool useTimeRange = false,
    String? timeFrom,
    String? timeTo,
    int? rubroId,
    int? subRubroId,
    int? sectorId,
    int? orderNumber,
  }) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = _uri('/api/reports/sales-detail',
          from: from,
          to: to,
          useTimeRange: useTimeRange,
          timeFrom: timeFrom,
          timeTo: timeTo,
          rubroId: rubroId,
          subRubroId: subRubroId,
          sectorId: sectorId,
          orderNumber: orderNumber);
      final data = _body(await http
              .get(uri, headers: _headers)
              .timeout(ApiConfig.timeout))['data'] as Map<String, dynamic>? ??
          const {};
      result = SalesReportResult.fromJson(data);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Uint8List> exportXlsx(
    String token, {
    DateTime? from,
    DateTime? to,
    bool useTimeRange = false,
    String? timeFrom,
    String? timeTo,
    int? rubroId,
    int? subRubroId,
    int? sectorId,
    int? orderNumber,
  }) async {
    _token = token;
    final uri = _uri('/api/reports/sales-detail/export',
        from: from,
        to: to,
        useTimeRange: useTimeRange,
        timeFrom: timeFrom,
        timeTo: timeTo,
        rubroId: rubroId,
        subRubroId: subRubroId,
        sectorId: sectorId,
        orderNumber: orderNumber);
    final response =
        await http.get(uri, headers: _headers).timeout(ApiConfig.timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'No se pudo exportar el listado (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  Uri _uri(
    String path, {
    DateTime? from,
    DateTime? to,
    required bool useTimeRange,
    String? timeFrom,
    String? timeTo,
    int? rubroId,
    int? subRubroId,
    int? sectorId,
    int? orderNumber,
  }) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: {
        if (from != null) 'from': _apiDate(from),
        if (to != null) 'to': _apiDate(to, endOfDay: true),
        'rangoHorario': '$useTimeRange',
        if (timeFrom != null) 'horaDesde': timeFrom,
        if (timeTo != null) 'horaHasta': timeTo,
        if (rubroId != null) 'rubroId': '$rubroId',
        if (subRubroId != null) 'subRubroId': '$subRubroId',
        if (sectorId != null) 'sectorId': '$sectorId',
        if (orderNumber != null) 'numeroPedido': '$orderNumber',
      });

  String _apiDate(DateTime date, {bool endOfDay = false}) => DateTime(
        date.year,
        date.month,
        date.day,
        endOfDay ? 23 : 0,
        endOfDay ? 59 : 0,
        endOfDay ? 59 : 0,
        endOfDay ? 999 : 0,
      ).toUtc().toIso8601String();

  Map<String, dynamic> _body(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          body['title']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
