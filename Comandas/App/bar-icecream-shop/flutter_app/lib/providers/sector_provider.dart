import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/restaurant_table.dart';
import '../models/sector.dart';

class SectorProvider extends ChangeNotifier {
  final List<Sector> _sectors = [];
  final List<RestaurantTable> _tables = [];
  String _token = '';
  bool _loading = false;
  String? _errorMessage;

  List<Sector> get sectors => List.unmodifiable(_sectors);
  List<RestaurantTable> get tables => List.unmodifiable(_tables);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<void> load({required String token}) async {
    _token = token;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final responses = await Future.wait([
        http.get(_uri('/api/sectors'), headers: _headers),
        http.get(_uri('/api/tables'), headers: _headers),
      ]).timeout(ApiConfig.timeout);
      final sectorData = _body(responses[0])['data'] as List<dynamic>? ?? [];
      final tableData = _body(responses[1])['data'] as List<dynamic>? ?? [];
      _sectors
        ..clear()
        ..addAll(sectorData
            .map((item) => Sector.fromJson(item as Map<String, dynamic>)));
      _tables
        ..clear()
        ..addAll(tableData.map(
            (item) => RestaurantTable.fromJson(item as Map<String, dynamic>)));
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Sector> saveSector({
    int? id,
    required String name,
    String description = '',
    int order = 0,
  }) async {
    // En el alta el id lo genera la API. Nombre, descripción y orden forman
    // parte del formulario y deben viajar tanto en POST como en PUT.
    final payload = jsonEncode({
      if (id != null) 'id': id,
      'name': name.trim(),
      'description': description.trim(),
      'order': order,
    });
    final response = id == null
        ? await http.post(_uri('/api/Sectors'),
            headers: _headers, body: payload)
        : await http.put(_uri('/api/Sectors/$id'),
            headers: _headers, body: payload);
    final data = _body(response)['data'];
    final saved = data is Map<String, dynamic>
        ? Sector.fromJson(data)
        : Sector(id: id ?? 0, name: name);
    await load(token: _token);
    final apiSector = _sectors.where((item) => item.id == saved.id).firstOrNull;
    final enriched = (apiSector ?? saved).copyWith(
      description: description,
      order: order,
    );
    final index = _sectors.indexWhere((item) => item.id == enriched.id);
    if (index != -1) _sectors[index] = enriched;
    notifyListeners();
    return enriched;
  }

  Future<void> deleteSector(int id) async {
    _body(await http.delete(_uri('/api/Sectors/$id'), headers: _headers));
    _sectors.removeWhere((item) => item.id == id);
    _tables.removeWhere((item) => item.sectorId == id);
    notifyListeners();
  }

  Future<void> setSectorActive(Sector sector, bool active) async {
    final response = await http.patch(
      _uri('/api/sectors/${sector.id}/status'),
      headers: _headers,
      body: jsonEncode({'active': active}),
    );
    final data = _body(response)['data'];
    final updated = data is Map<String, dynamic>
        ? Sector.fromJson(data)
        : sector.copyWith(active: active);
    final index = _sectors.indexWhere((item) => item.id == sector.id);
    if (index != -1) _sectors[index] = updated;
    notifyListeners();
  }

  Future<RestaurantTable> addTable({
    required int sectorId,
    required String name,
    required String description,
    required String shape,
    required int capacity,
    double positionX = .44,
    double positionY = .42,
  }) async {
    final response = await http.post(
      _uri('/api/tables'),
      headers: _headers,
      body: jsonEncode({
        'name': name.trim(),
        'description': description.trim(),
        'sectorId': sectorId,
        'shape': shape,
        'capacity': capacity,
        'positionX': positionX,
        'positionY': positionY,
      }),
    );
    final saved = RestaurantTable.fromJson(
        _body(response)['data'] as Map<String, dynamic>);
    _tables.add(saved);
    notifyListeners();
    return saved;
  }

  Future<void> updateTable(RestaurantTable table) async {
    _body(await http.put(
      _uri('/api/Tables/${table.id}'),
      headers: _headers,
      body: jsonEncode({
        'name': table.name,
        'description': table.description,
        'sectorId': table.sectorId,
        'shape': table.shape,
        'capacity': table.capacity,
        'positionX': table.positionX,
        'positionY': table.positionY,
      }),
    ));
  }

  Future<void> setTableActive(RestaurantTable table, bool active) async {
    final response = await http.patch(
      _uri('/api/tables/${table.id}/status'),
      headers: _headers,
      body: jsonEncode({'active': active}),
    );
    final data = _body(response)['data'];
    final updated = data is Map<String, dynamic>
        ? RestaurantTable.fromJson(data)
        : RestaurantTable(
            id: table.id,
            number: table.number,
            name: table.name,
            description: table.description,
            sectorId: table.sectorId,
            status: table.status,
            shape: table.shape,
            type: table.type,
            capacity: table.capacity,
            active: active,
            positionX: table.positionX,
            positionY: table.positionY,
          );
    final index = _tables.indexWhere((item) => item.id == table.id);
    if (index != -1) _tables[index] = updated;
    notifyListeners();
  }

  Map<String, dynamic> _body(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_apiError(decoded, response.statusCode));
    }
    return decoded;
  }

  String _apiError(Map<String, dynamic> body, int statusCode) {
    final validation = body['errors'];
    if (validation is Map<String, dynamic> && validation.isNotEmpty) {
      final messages = <String>[];
      for (final entry in validation.entries) {
        final value = entry.value;
        if (value is List) {
          messages.addAll(value.map((item) => item.toString()));
        } else {
          messages.add(value.toString());
        }
      }
      if (messages.isNotEmpty) return messages.join('\n');
    }
    return body['error']?.toString() ??
        body['detail']?.toString() ??
        body['title']?.toString() ??
        'Error del servidor ($statusCode).';
  }
}
