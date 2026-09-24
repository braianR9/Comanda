import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/caja.dart';

class CajaProvider extends ChangeNotifier {
  Caja? _current;
  List<Caja> _history = [];
  bool _loading = false;
  String? _errorMessage;
  String _token = '';

  Caja? get current => _current;
  bool get isOpen => _current != null && _current!.abierta;
  List<Caja> get history => List.unmodifiable(_history);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(String token) async {
    _token = token;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http
          .get(_uri('/api/cajas/actual'), headers: _headers)
          .timeout(ApiConfig.timeout);
      final data = _body(response)['data'];
      _current =
          data == null ? null : Caja.fromJson(data as Map<String, dynamic>);
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory({int take = 20}) async {
    final response = await http
        .get(_uri('/api/cajas', {'take': '$take'}), headers: _headers)
        .timeout(ApiConfig.timeout);
    final items = _body(response)['data'] as List<dynamic>? ?? const [];
    _history =
        items.map((e) => Caja.fromJson(e as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  Future<Caja> abrir(
      {required double montoInicial, String? observaciones}) async {
    final response = await http
        .post(_uri('/api/cajas/abrir'),
            headers: _headers,
            body: jsonEncode({
              'montoInicial': montoInicial,
              'observaciones': observaciones,
            }))
        .timeout(ApiConfig.timeout);
    final caja = Caja.fromJson(_body(response)['data'] as Map<String, dynamic>);
    _current = caja;
    notifyListeners();
    return caja;
  }

  Future<Caja> cerrar({String? observaciones}) async {
    final caja = _current;
    if (caja == null) throw Exception('No hay una caja abierta.');
    final response = await http
        .post(_uri('/api/cajas/${caja.id}/cerrar'),
            headers: _headers,
            body: jsonEncode({'observaciones': observaciones}))
        .timeout(ApiConfig.timeout);
    final closed =
        Caja.fromJson(_body(response)['data'] as Map<String, dynamic>);
    _current = null;
    unawaited(loadHistory());
    notifyListeners();
    return closed;
  }

  Future<CajaMovimiento> agregarMovimiento({
    required String tipo,
    required double monto,
    required String motivo,
  }) async {
    final caja = _current;
    if (caja == null) throw Exception('No hay una caja abierta.');
    final response = await http
        .post(_uri('/api/cajas/${caja.id}/movimientos'),
            headers: _headers,
            body: jsonEncode({'tipo': tipo, 'monto': monto, 'motivo': motivo}))
        .timeout(ApiConfig.timeout);
    final movimiento = CajaMovimiento.fromJson(
        _body(response)['data'] as Map<String, dynamic>);
    await load(_token);
    return movimiento;
  }

  Future<Caja> refreshCurrent() async {
    await load(_token);
    final caja = _current;
    if (caja == null) throw Exception('No hay una caja abierta.');
    return caja;
  }

  Future<void> enqueuePrint(int cajaId) async {
    final printersResponse = await http
        .get(_uri('/api/printers'), headers: _headers)
        .timeout(ApiConfig.timeout);
    final values = _body(printersResponse)['data'] as List? ?? const [];
    final printers = values.whereType<Map<String, dynamic>>().where((item) {
      final usage = item['usage']?.toString().toLowerCase() ?? '';
      return item['active'] != false &&
          (usage.isEmpty ||
              usage == 'ambos' ||
              usage.contains('ticket') ||
              usage.contains('venta'));
    }).toList();
    if (printers.isEmpty) {
      throw Exception('No hay una impresora activa configurada para tickets.');
    }
    final printer =
        printers.where((item) => item['isDefault'] == true).firstOrNull ??
            printers.first;
    _body(await http
        .post(
          _uri('/api/Printer'),
          headers: _headers,
          body: jsonEncode({
            'cajaId': cajaId,
            'printerId': printer['queueName']?.toString(),
            'printerConfigurationId': (printer['id'] as num).toInt(),
            'jobType': 'CierreCaja',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'Pending',
          }),
        )
        .timeout(ApiConfig.timeout));
  }

  Map<String, dynamic> _body(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
