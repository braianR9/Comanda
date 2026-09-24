import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/product.dart';
import '../models/product_group.dart';
import '../models/product_tax.dart';

class ProductProvider extends ChangeNotifier {
  final List<Product> _products = [];
  final List<ProductGroup> _groups = [];
  final List<ProductTax> _taxes = [];
  int? _companyId;
  bool _loading = false;
  bool _loaded = false;
  String? _errorMessage;
  String _token = '';
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  static const int pageSize = 10;

  List<Product> get products => List.unmodifiable(_products);
  List<ProductGroup> get groups => List.unmodifiable(_groups);
  List<ProductTax> get taxes => List.unmodifiable(_taxes);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalItems => _totalItems;
  Map<String, String> get imageHeaders => {
        ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  String resolveImageUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://')
          ? url
          : '${ApiConfig.baseUrl}$url';

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(int companyId,
      {String token = '', bool force = false}) async {
    final tokenChanged = _token != token;
    _token = token;
    if (_companyId == companyId && _loaded && !force && !tokenChanged) return;
    _companyId = companyId;
    _loading = true;
    _loaded = false;
    _errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([_loadProducts(page: 1), _loadGroups(), _loadTaxes()]);
      _loaded = true;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      _loaded = false;
      debugPrint('Product API load error: $error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProducts({required int page, String? text}) async {
    final response = await http
        .get(
            _uri('/api/productos', {
              'page': '$page',
              'pageSize': '$pageSize',
              if (text != null && text.trim().isNotEmpty) 'texto': text.trim(),
            }),
            headers: _headers)
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>? ?? const {};
    final items = data['items'] as List<dynamic>? ?? const [];
    _currentPage = data['page'] as int? ?? page;
    _totalPages = data['totalPages'] as int? ?? 1;
    _totalItems = data['totalItems'] as int? ?? items.length;
    _products
      ..clear()
      ..addAll(
          items.map((item) => _productFromApi(item as Map<String, dynamic>)));
  }

  Future<void> loadProductsPage({required int page, String? text}) async {
    if (_loading || page < 1 || (page > _totalPages && _totalItems > 0)) return;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _loadProducts(page: page, text: text);
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadGroups() async {
    final response = await http
        .get(_uri('/api/rubros', {'activo': 'true'}), headers: _headers)
        .timeout(ApiConfig.timeout);
    final items = _body(response)['data'] as List<dynamic>? ?? const [];
    _groups.clear();
    for (final raw in items) {
      final json = raw as Map<String, dynamic>;
      final parent = _groupFromApi(json);
      _groups.add(parent);
      for (final child in json['subRubros'] as List<dynamic>? ?? const []) {
        _groups.add(
            _groupFromApi(child as Map<String, dynamic>, parentId: parent.id));
      }
    }
  }

  Future<void> _loadTaxes() async {
    final response = await http
        .get(_uri('/api/alicuotas', {'activo': 'true'}), headers: _headers)
        .timeout(ApiConfig.timeout);
    final items = _body(response)['data'] as List<dynamic>? ?? const [];
    _taxes
      ..clear()
      ..addAll(items
          .map((item) => ProductTax.fromJson(item as Map<String, dynamic>)));
  }

  Future<Product> getById(String id) async {
    final response = await http
        .get(_uri('/api/productos/$id'), headers: _headers)
        .timeout(ApiConfig.timeout);
    return _productFromApi(_body(response)['data'] as Map<String, dynamic>);
  }

  // Trae todos los códigos de la sucursal/empresa actual para sugerir el siguiente.
  Future<int> fetchNextProductCode() async {
    final size = _totalItems > 0 ? _totalItems : pageSize;
    final response = await http
        .get(_uri('/api/productos', {'page': '1', 'pageSize': '$size'}),
            headers: _headers)
        .timeout(ApiConfig.timeout);
    final data = _body(response)['data'] as Map<String, dynamic>? ?? const {};
    final items = data['items'] as List<dynamic>? ?? const [];
    var maxCode = 0;
    for (final item in items) {
      final code = int.tryParse(
          (item as Map<String, dynamic>)['codigo']?.toString() ?? '');
      if (code != null && code > maxCode) maxCode = code;
    }
    return maxCode + 1;
  }

  Future<void> save(Product product) async {
    final index = _products.indexWhere((item) => item.id == product.id);
    final creating = index == -1;
    final rubro = _groups.firstWhere(
      (item) => !item.isSubgroup && item.name == product.category,
      orElse: () => throw Exception('Seleccioná un rubro válido.'),
    );
    ProductGroup? subRubro;
    for (final item in _groups) {
      if (item.parentId == rubro.id && item.name == product.subcategory) {
        subRubro = item;
      }
    }
    final payload = {
      'codigo': int.parse(product.code),
      'nombre': product.name,
      'descripcion': product.description,
      'tipoProducto': product.type.replaceAll(' ', ''),
      'idRubro': int.parse(rubro.id),
      'idSubRubro': subRubro == null ? null : int.parse(subRubro.id),
      'idAlicuota': int.parse(product.taxId),
      'costoConIva': product.cost,
      'precioConIva': product.price,
      'mostrarDelivery': product.showDelivery,
      'mostrarSalon': product.showSalon,
      'mostrarCartaDigital': product.showDigitalMenu,
      'solicitarCantidad': false,
      'solicitarPrecioUnitario': false,
      'solicitarPrecioYCalcularCantidad': false,
      'preparacion': null,
      'orden': 0,
      'stock': {
        'operacionCantidad': product.quantityOperation,
        'stockActual': product.currentStock,
        'stockMinimo': product.minimumStock,
        'stockIdeal': product.idealStock,
        'tieneAlarmaStock': product.stockAlarm,
        'tieneAlarmaStockMinimo': product.minimumStockAlarm,
        'comprobarStockAlVender': product.checkStockOnSale,
        'actualizarSobre': product.stockUpdatesOn,
      },
    };
    final response = creating
        ? await http
            .post(_uri('/api/productos'),
                headers: _headers, body: jsonEncode(payload))
            .timeout(ApiConfig.timeout)
        : await http
            .put(_uri('/api/productos/${product.id}'),
                headers: _headers, body: jsonEncode(payload))
            .timeout(ApiConfig.timeout);
    var saved =
        _productFromApi(_body(response)['data'] as Map<String, dynamic>);
    if (product.imageBase64 != null && product.imageBase64!.isNotEmpty) {
      saved = _productFromApi(await _uploadRaw(
          '/api/productos/${saved.id}/imagen', product.imageBase64!));
    }
    if (creating) {
      _products.add(saved);
    } else {
      _products[index] = saved;
    }
    notifyListeners();
  }

  Future<void> setActive(Product product, bool active) async {
    final response = await http
        .patch(_uri('/api/productos/${product.id}/estado'),
            headers: _headers, body: jsonEncode({'activo': active}))
        .timeout(ApiConfig.timeout);
    _body(response);
    final index = _products.indexWhere((item) => item.id == product.id);
    if (index != -1) _products[index] = product.copyWith(active: active);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final response = await http
        .delete(_uri('/api/productos/$id'), headers: _headers)
        .timeout(ApiConfig.timeout);
    _body(response);
    _products.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  Future<ProductGroup> saveGroup(ProductGroup group) async {
    final payload = {
      'nombre': group.name,
      'descripcion': group.description,
      'tipoObservacion': group.observationType,
      'aplicarProductos': group.applyProducts,
      if (group.isSubgroup) 'aplicarIngredientes': group.applyIngredients,
      'aplicarDelivery': group.applyDelivery,
      'aplicarSalon': group.applySalon,
      'mostrarCartaDigital': group.showDigitalMenu,
    };
    final path = group.isSubgroup
        ? '/api/rubros/${group.parentId}/subrubros'
        : '/api/rubros';
    final response = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(payload))
        .timeout(ApiConfig.timeout);
    var saved = _groupFromApi(_body(response)['data'] as Map<String, dynamic>,
        parentId: group.parentId);
    if (group.imageBase64 != null && group.imageBase64!.isNotEmpty) {
      saved = _groupFromApi(
        await _uploadRaw(
            saved.isSubgroup
                ? '/api/subrubros/${saved.id}/imagen'
                : '/api/rubros/${saved.id}/imagen',
            group.imageBase64!),
        parentId: group.parentId,
      );
    }
    _groups.add(saved);
    notifyListeners();
    return saved;
  }

  Future<ProductTax> saveTax(ProductTax tax) async {
    final response = await http
        .post(_uri('/api/alicuotas'),
            headers: _headers,
            body: jsonEncode({
              'nombre': tax.name,
              'descripcion': tax.description,
              'porcentaje': tax.percentage,
            }))
        .timeout(ApiConfig.timeout);
    final saved =
        ProductTax.fromJson(_body(response)['data'] as Map<String, dynamic>);
    _taxes.add(saved);
    notifyListeners();
    return saved;
  }

  Future<Map<String, dynamic>> _uploadRaw(String path, String base64) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers[ApiConfig.apiKeyHeader] = ApiConfig.apiKeyValue
      ..headers.addAll(
          _token.isEmpty ? const {} : {'Authorization': 'Bearer $_token'})
      ..files.add(http.MultipartFile.fromBytes('Imagen', base64Decode(base64),
          filename: 'imagen.png'));
    final response = await http.Response.fromStream(
        await request.send().timeout(ApiConfig.timeout));
    return _body(response)['data'] as Map<String, dynamic>;
  }

  Map<String, dynamic> _body(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }

  Product _productFromApi(Map<String, dynamic> json) {
    final rubro = json['rubro'] as Map<String, dynamic>?;
    final sub = json['subRubro'] as Map<String, dynamic>?;
    final tax = json['alicuota'] as Map<String, dynamic>?;
    final stock = json['stock'] as Map<String, dynamic>?;
    return Product(
      id: json['id'].toString(),
      code: json['codigo']?.toString() ?? '',
      name: json['nombre']?.toString() ?? '',
      category: rubro?['nombre']?.toString() ?? '',
      subcategory: sub?['nombre']?.toString() ?? '',
      price: (json['precioConIva'] as num?)?.toDouble() ?? 0,
      active: json['activo'] as bool? ?? true,
      imageUrl: json['imagenUrl']?.toString(),
      description: json['descripcion']?.toString() ?? '',
      type: json['tipoProducto'] == 'ProductoSimple'
          ? 'Producto simple'
          : json['tipoProducto']?.toString() ?? 'Producto simple',
      cost: (json['costoConIva'] as num?)?.toDouble() ?? 0,
      taxRate: (tax?['porcentaje'] as num?)?.toDouble() ?? 21,
      taxId: tax?['id']?.toString() ?? '',
      quantityOperation: stock?['operacionCantidad']?.toString() ?? 'Entero',
      currentStock: (stock?['stockActual'] as num?)?.toDouble() ?? 0,
      minimumStock: (stock?['stockMinimo'] as num?)?.toDouble() ?? 0,
      idealStock: (stock?['stockIdeal'] as num?)?.toDouble() ?? 1,
      stockAlarm: stock?['tieneAlarmaStock'] as bool? ?? false,
      minimumStockAlarm: stock?['tieneAlarmaStockMinimo'] as bool? ?? false,
      checkStockOnSale: stock?['comprobarStockAlVender'] as bool? ?? false,
      stockUpdatesOn: stock?['actualizarSobre']?.toString() ?? 'Producto',
      showDelivery: json['mostrarDelivery'] as bool? ?? true,
      showSalon: json['mostrarSalon'] as bool? ?? true,
      showDigitalMenu: json['mostrarCartaDigital'] as bool? ?? true,
    );
  }

  ProductGroup _groupFromApi(Map<String, dynamic> json, {String? parentId}) =>
      ProductGroup(
        id: json['id'].toString(),
        name: json['nombre']?.toString() ?? '',
        description: json['descripcion']?.toString() ?? '',
        observationType: json['tipoObservacion']?.toString() ?? '',
        parentId: parentId ?? json['idRubro']?.toString(),
        imageUrl: json['imagenUrl']?.toString(),
        applyProducts: json['aplicarProductos'] as bool? ?? true,
        applyIngredients: json['aplicarIngredientes'] as bool? ?? false,
        applyDelivery: json['aplicarDelivery'] as bool? ?? true,
        applySalon: json['aplicarSalon'] as bool? ?? true,
        showDigitalMenu: json['mostrarCartaDigital'] as bool? ?? true,
      );
}
