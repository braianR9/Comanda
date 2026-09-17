import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ConfiguredPrinter {
  final int id;
  final String name;
  final String connectionType;
  final String? queueName;
  final String? ipAddress;
  final int? port;
  final String usage;
  final bool isDefault;
  final bool active;

  const ConfiguredPrinter({
    this.id = 0,
    required this.name,
    required this.connectionType,
    this.queueName,
    this.ipAddress,
    this.port,
    required this.usage,
    this.isDefault = false,
    this.active = true,
  });

  factory ConfiguredPrinter.fromJson(Map<String, dynamic> json) =>
      ConfiguredPrinter(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        connectionType: json['connectionType']?.toString() ?? 'Cups',
        queueName: json['queueName']?.toString(),
        ipAddress: json['ipAddress']?.toString(),
        port: (json['port'] as num?)?.toInt(),
        usage: json['usage']?.toString() ?? 'Ambos',
        isDefault: json['isDefault'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );

  Map<String, dynamic> toRequest() => {
        'name': name,
        'connectionType': connectionType,
        'queueName': connectionType == 'Cups' ? queueName : null,
        'ipAddress': connectionType == 'Red' ? ipAddress : null,
        'port': connectionType == 'Red' ? port : null,
        'usage': usage,
        'isDefault': isDefault,
        'active': active,
      };
}

class PrinterProvider extends ChangeNotifier {
  String _token = '';
  bool loading = false;
  String? error;
  List<ConfiguredPrinter> printers = [];

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(String token) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response = await http
          .get(
              Uri.parse(
                  '${ApiConfig.baseUrl}/api/printers?includeInactive=true'),
              headers: _headers)
          .timeout(ApiConfig.timeout);
      final values = _body(response)['data'] as List? ?? const [];
      printers = [
        for (final value in values)
          ConfiguredPrinter.fromJson(value as Map<String, dynamic>)
      ];
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> save(ConfiguredPrinter printer) async {
    const base = '${ApiConfig.baseUrl}/api/printers';
    final response = printer.id == 0
        ? await http.post(Uri.parse(base),
            headers: _headers, body: jsonEncode(printer.toRequest()))
        : await http.put(Uri.parse('$base/${printer.id}'),
            headers: _headers, body: jsonEncode(printer.toRequest()));
    _body(response);
    await load(_token);
  }

  Future<void> setActive(ConfiguredPrinter printer, bool active) async {
    _body(await http
        .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/printers/${printer.id}/status'),
            headers: _headers,
            body: jsonEncode({'active': active}))
        .timeout(ApiConfig.timeout));
    await load(_token);
  }

  Future<void> test(ConfiguredPrinter printer) async {
    _body(await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/printers/${printer.id}/test'),
            headers: _headers)
        .timeout(ApiConfig.timeout));
  }

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
