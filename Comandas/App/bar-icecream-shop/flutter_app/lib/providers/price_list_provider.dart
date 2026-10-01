import '../utils/api_response.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/price_list.dart';

class PagedProductPrices {
  final List<ProductPrice> items;
  final int page;
  final int totalPages;
  final int totalItems;
  const PagedProductPrices({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalItems,
  });
}

class PriceListProvider extends ChangeNotifier {
  final List<PriceList> _lists = [];
  bool _loading = false;
  String? _errorMessage;
  String _token = '';

  List<PriceList> get lists => List.unmodifiable(_lists);
  List<PriceList> get activeLists => _lists.where((l) => l.activa).toList();
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  PriceList? get defaultList =>
      _lists.where((l) => l.esPredeterminada).firstOrNull;

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
          .get(_uri('/api/listas-precios'), headers: _headers)
          .timeout(ApiConfig.timeout);
      final items = _body(response)['data'] as List<dynamic>? ?? const [];
      _lists
        ..clear()
        ..addAll(
            items.map((e) => PriceList.fromJson(e as Map<String, dynamic>)));
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<PriceList> create(
      {required String nombre, int? copiarDesdeListaId}) async {
    final response = await http
        .post(_uri('/api/listas-precios'),
            headers: _headers,
            body: jsonEncode({
              'nombre': nombre,
              'copiarDesdeListaId': copiarDesdeListaId,
            }))
        .timeout(ApiConfig.timeout);
    final created =
        PriceList.fromJson(_body(response)['data'] as Map<String, dynamic>);
    _lists.add(created);
    notifyListeners();
    return created;
  }

  Future<void> rename(int id, String nombre) async {
    final response = await http
        .put(_uri('/api/listas-precios/$id'),
            headers: _headers, body: jsonEncode({'nombre': nombre}))
        .timeout(ApiConfig.timeout);
    _replace(
        PriceList.fromJson(_body(response)['data'] as Map<String, dynamic>));
  }

  Future<void> setActive(int id, bool activa) async {
    final response = await http
        .patch(_uri('/api/listas-precios/$id/estado'),
            headers: _headers, body: jsonEncode({'activa': activa}))
        .timeout(ApiConfig.timeout);
    _replace(
        PriceList.fromJson(_body(response)['data'] as Map<String, dynamic>));
  }

  Future<void> setDefault(int id) async {
    final response = await http
        .patch(_uri('/api/listas-precios/$id/predeterminada'),
            headers: _headers)
        .timeout(ApiConfig.timeout);
    final updated =
        PriceList.fromJson(_body(response)['data'] as Map<String, dynamic>);
    for (var i = 0; i < _lists.length; i++) {
      if (_lists[i].esPredeterminada && _lists[i].id != updated.id) {
        _lists[i] = PriceList(
          id: _lists[i].id,
          nombre: _lists[i].nombre,
          esPredeterminada: false,
          activa: _lists[i].activa,
          fechaCreacion: _lists[i].fechaCreacion,
          fechaModificacion: DateTime.now(),
          cantidadPrecios: _lists[i].cantidadPrecios,
        );
      }
    }
    _replace(updated);
  }

  Future<void> remove(int id) async {
    final response = await http
        .delete(_uri('/api/listas-precios/$id'), headers: _headers)
        .timeout(ApiConfig.timeout);
    _body(response);
    _lists.removeWhere((l) => l.id == id);
    notifyListeners();
  }

  Future<PagedProductPrices> getPrices(
    int listId, {
    int? idRubro,
    int? idSubRubro,
    String? texto,
    int page = 1,
    int pageSize = 30,
  }) async {
    final response = await http
        .get(
            _uri('/api/listas-precios/$listId/precios', {
              'page': '$page',
              'pageSize': '$pageSize',
              if (idRubro != null) 'idRubro': '$idRubro',
              if (idSubRubro != null) 'idSubRubro': '$idSubRubro',
              if (texto != null && texto.trim().isNotEmpty)
                'texto': texto.trim(),
            }),
            headers: _headers)
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>? ?? const {};
    final items = data['items'] as List<dynamic>? ?? const [];
    return PagedProductPrices(
      items: items
          .map((e) => ProductPrice.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: data['page'] as int? ?? page,
      totalPages: data['totalPages'] as int? ?? 1,
      totalItems: data['totalItems'] as int? ?? items.length,
    );
  }

  Future<double> setPrice(int listId, int productId, double precio) async {
    final response = await http
        .put(_uri('/api/listas-precios/$listId/precios/$productId'),
            headers: _headers, body: jsonEncode({'precio': precio}))
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>;
    return (data['precio'] as num?)?.toDouble() ?? precio;
  }

  Future<List<BulkPricePreviewItem>> previewBulk(
    int listId, {
    int? idRubro,
    int? idSubRubro,
    String? texto,
    List<int>? productoIds,
    required String operacion,
    required double valor,
    double redondeo = 0,
    String modoRedondeo = 'Arriba',
    List<BulkPricePreviewItem>? confirmados,
  }) async {
    final response = await http
        .post(_uri('/api/listas-precios/$listId/precios/vista-previa-masiva'),
            headers: _headers,
            body: jsonEncode({
              'filtro': {
                'idRubro': idRubro,
                'idSubRubro': idSubRubro,
                'texto': texto,
                'productoIds': productoIds,
              },
              'operacion': operacion,
              'valor': valor,
              'redondeo': redondeo,
              'modoRedondeo': modoRedondeo,
              if (confirmados != null)
                'cambiosConfirmados': confirmados
                    .map((p) => {
                          'idListaPrecio': listId,
                          'idProducto': p.idProducto,
                          'precioAnterior': p.precioActual,
                          'precioNuevo': p.precioNuevo,
                        })
                    .toList(),
            }))
        .timeout(ApiConfig.timeout);
    final items = _body(response)['data'] as List<dynamic>? ?? const [];
    return items
        .map((e) => BulkPricePreviewItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> applyBulk(
    int listId, {
    int? idRubro,
    int? idSubRubro,
    String? texto,
    List<int>? productoIds,
    required String operacion,
    required double valor,
    double redondeo = 0,
    String modoRedondeo = 'Arriba',
    List<BulkPricePreviewItem>? confirmados,
  }) async {
    final response = await http
        .post(_uri('/api/listas-precios/$listId/precios/aplicar-masivo'),
            headers: _headers,
            body: jsonEncode({
              'filtro': {
                'idRubro': idRubro,
                'idSubRubro': idSubRubro,
                'texto': texto,
                'productoIds': productoIds,
              },
              'operacion': operacion,
              'valor': valor,
              'redondeo': redondeo,
              'modoRedondeo': modoRedondeo,
              if (confirmados != null)
                'cambiosConfirmados': confirmados
                    .map((p) => {
                          'idListaPrecio': listId,
                          'idProducto': p.idProducto,
                          'precioAnterior': p.precioActual,
                          'precioNuevo': p.precioNuevo,
                        })
                    .toList(),
            }))
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>;
    return (data['actualizados'] as num?)?.toInt() ?? 0;
  }

  Future<void> saveGrid(List<Map<String, dynamic>> changes) async {
    _body(await http
        .put(_uri('/api/listas-precios/planilla'),
            headers: _headers, body: jsonEncode({'cambios': changes}))
        .timeout(ApiConfig.timeout));
  }

  Future<Map<String, dynamic>> history(int page) async => _body(await http
      .get(_uri('/api/listas-precios/historial', {'page': '$page'}),
          headers: _headers)
      .timeout(ApiConfig.timeout))['data'] as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> historyDetails(String batch) async {
    final body = _body(await http
        .get(_uri('/api/listas-precios/historial/$batch'), headers: _headers)
        .timeout(ApiConfig.timeout));
    return (body['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> revert(String batch) async {
    _body(await http
        .post(_uri('/api/listas-precios/historial/$batch/revertir'),
            headers: _headers)
        .timeout(ApiConfig.timeout));
  }

  Future<List<Map<String, dynamic>>> rules(int listId) async {
    final body = _body(await http
        .get(_uri('/api/listas-precios/$listId/reglas'), headers: _headers)
        .timeout(ApiConfig.timeout));
    return (body['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveRule(int listId, Map<String, dynamic> rule,
      {int? id}) async {
    final uri =
        _uri('/api/listas-precios/$listId/reglas${id == null ? '' : '/$id'}');
    final response = id == null
        ? await http
            .post(uri, headers: _headers, body: jsonEncode(rule))
            .timeout(ApiConfig.timeout)
        : await http
            .put(uri, headers: _headers, body: jsonEncode(rule))
            .timeout(ApiConfig.timeout);
    _body(response);
  }

  Future<Map<int, Map<String, dynamic>>> quotePrices(List<int> productIds,
      {int? listId, DateTime? instant}) async {
    if (productIds.isEmpty) return {};
    final body = _body(await http
        .post(_uri('/api/listas-precios/consulta-precios'),
            headers: _headers,
            body: jsonEncode({
              'idListaPrecio': listId,
              'productoIds': productIds,
              if (instant != null) 'fecha': instant.toUtc().toIso8601String()
            }))
        .timeout(ApiConfig.timeout));
    return {
      for (final row in (body['data'] as List).cast<Map<String, dynamic>>())
        (row['idProducto'] as num).toInt(): row
    };
  }

  void _replace(PriceList updated) {
    final index = _lists.indexWhere((l) => l.id == updated.id);
    if (index != -1) _lists[index] = updated;
    notifyListeners();
  }

  Map<String, dynamic> _body(http.Response response) {
    final body = decodeApiResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
