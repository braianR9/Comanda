import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/api_response.dart';
import '../utils/client_diagnostics.dart';

class SystemAdminProvider extends ChangeNotifier {
  final http.Client _client;
  SystemAdminProvider({http.Client? client})
      : _client = client ?? http.Client();
  String? _token;
  bool _disposed = false;
  int _generation = 0;
  String email = '';
  bool busy = false;
  String? error;
  int section = 0;
  int? companyId;
  int? branchId;
  String? status;
  bool? resolved;
  String transactionKind = 'sales';
  String search = '';
  DateTime from =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime to = DateTime.now();
  int page = 1;
  int total = 0;
  static const pageSize = 30;
  num amount = 0;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> daily = [];
  List<Map<String, dynamic>> companies = [];
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> roles = [];
  bool get authenticated => _token != null;
  bool get hasNext => page * pageSize < total;

  // La sesión de sistemas queda solamente en memoria y vence a los 30 minutos.
  Future<dynamic> request(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/system/$path')
        .replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        ...ApiConfig.headers,
        if (_token != null) 'Authorization': 'Bearer $_token',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
            await _client.send(request).timeout(const Duration(seconds: 25)))
        .timeout(const Duration(seconds: 25));
    final decoded = decodeApiResponse(response);
    if (response.statusCode == 401 && _token != null) {
      logout();
      error = 'La sesión de sistemas venció. Volvé a ingresar.';
      _notify();
    }
    if (response.statusCode >= 400 ||
        (decoded['codigo'] as int? ?? 200) >= 400) {
      throw Exception(decoded['error'] ?? 'No se pudo completar la operación.');
    }
    return decoded['data'];
  }

  Future<void> login(String userEmail, String password) async {
    busy = true;
    error = null;
    _notify();
    try {
      final data = await request('POST', 'login',
          body: {'email': userEmail.trim(), 'password': password});
      _token = data['token'] as String;
      ClientDiagnostics.ownerToken = _token;
      email = data['email'] as String;
      roles = _list(await request('GET', 'roles'));
      await load();
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void logout() {
    ClientDiagnostics.ownerToken = null;
    _generation++;
    _token = null;
    email = '';
    error = null;
    busy = false;
    companyId = null;
    branchId = null;
    page = 1;
    section = 0;
    total = 0;
    amount = 0;
    search = '';
    rows = [];
    daily = [];
    companies = [];
    branches = [];
    roles = [];
    _notify();
  }

  Future<void> selectCompany(Map<String, dynamic> company,
      {int? openSection}) async {
    busy = true;
    companyId = company['id'] as int;
    branchId = null;
    page = 1;
    search = '';
    companies = [company];
    if (openSection != null) section = openSection;
    _notify();
    try {
      branches = _list(await request('GET', 'companies/$companyId/branches'));
      await load();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> changeSection(int value) async {
    section = value;
    page = 1;
    search = '';
    await load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    busy = true;
    error = null;
    _notify();
    try {
      if (section == 1 && companyId == null) {
        rows = [];
        total = 0;
        return;
      }
      String path;
      final query = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (section == 0) {
        path = 'companies';
        query['search'] = search;
      } else if (section == 1) {
        path = 'companies/$companyId/users';
        query['search'] = search;
      } else {
        path = section == 2 ? 'transactions' : 'events';
        final end = DateTime(to.year, to.month, to.day + 1);
        query.addAll({
          'from': DateTime(from.year, from.month, from.day)
              .toUtc()
              .toIso8601String(),
          'to': end.toUtc().toIso8601String(),
          if (companyId != null) 'company': '$companyId',
          if (branchId != null) 'branch': '$branchId',
        });
        if (section == 2) {
          query.addAll({
            'kind': transactionKind,
            'utcOffsetMinutes': '${from.timeZoneOffset.inMinutes}',
            if (status != null) 'status': status!
          });
        } else {
          query.addAll({
            'type': section == 3 ? 'Error' : 'Audit',
            'search': search,
            if (section == 3 && resolved != null) 'resolved': '$resolved'
          });
        }
      }
      final data =
          await request('GET', path, query: query) as Map<String, dynamic>;
      if (generation != _generation || !authenticated) return;
      rows = _list(data['items']);
      total = data['total'] as int;
      amount = data['amount'] as num? ?? 0;
      daily = _list(data['daily'] ?? []);
    } catch (e) {
      if (generation == _generation) {
        rows = [];
        daily = [];
        total = 0;
        error = _message(e);
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> save(String path, Map<String, dynamic> data,
      {bool create = false}) async {
    busy = true;
    _notify();
    try {
      final result = await request(create ? 'POST' : 'PUT', path, body: data);
      if (path == 'companies/$companyId') {
        companies = [Map<String, dynamic>.from(result as Map)];
      }
      if (companyId != null) {
        branches = _list(await request('GET', 'companies/$companyId/branches'));
      }
      await load();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> changePassword(String current, String next) async {
    final previous = _token;
    final data = await request('PUT', 'password',
        body: {'currentPassword': current, 'newPassword': next});
    if (_token == null || _token != previous || _disposed) return;
    _token = data['token'] as String;
    ClientDiagnostics.ownerToken = _token;
  }

  static List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  static String _message(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (ClientDiagnostics.ownerToken == _token) {
      ClientDiagnostics.ownerToken = null;
    }
    _disposed = true;
    _generation++;
    _client.close();
    super.dispose();
  }
}
