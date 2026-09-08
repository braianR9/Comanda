import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class Customer {
  final int id;
  final int code;
  final String name;
  final String priceList;
  final String vatCondition;
  final String documentType;
  final String documentNumber;
  final String phone;
  final String email;
  final DateTime? birthday;
  final bool active;

  const Customer({
    this.id = 0,
    this.code = 0,
    required this.name,
    this.priceList = 'Predeterminada',
    required this.vatCondition,
    required this.documentType,
    this.documentNumber = '',
    this.phone = '',
    this.email = '',
    this.birthday,
    this.active = true,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: (json['id'] as num?)?.toInt() ?? 0,
        code: (json['code'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        priceList: json['priceList']?.toString() ?? 'Predeterminada',
        vatCondition: json['vatCondition']?.toString() ?? '',
        documentType: json['documentType']?.toString() ?? '',
        documentNumber: json['documentNumber']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        birthday: DateTime.tryParse(json['birthday']?.toString() ?? ''),
        active: json['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceList': priceList,
        'vatCondition': vatCondition,
        'documentType': documentType,
        'documentNumber': documentNumber.isEmpty ? null : documentNumber,
        'phone': phone.isEmpty ? null : phone,
        'email': email.isEmpty ? null : email,
        'birthday': birthday == null
            ? null
            : '${birthday!.year.toString().padLeft(4, '0')}-${birthday!.month.toString().padLeft(2, '0')}-${birthday!.day.toString().padLeft(2, '0')}',
        'active': active,
      };
}

class CustomerProvider extends ChangeNotifier {
  bool loading = false;
  String? error;
  List<Customer> customers = [];
  String _token = '';

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(String token, {bool includeInactive = false}) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/customers')
          .replace(queryParameters: {'includeInactive': '$includeInactive'});
      final data = _body(await http
              .get(uri, headers: _headers)
              .timeout(ApiConfig.timeout))['data'] as List? ??
          const [];
      customers = [
        for (final item in data) Customer.fromJson(item as Map<String, dynamic>)
      ];
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> save(Customer customer) async {
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/customers${customer.id == 0 ? '' : '/${customer.id}'}');
    final response = customer.id == 0
        ? await http
            .post(uri, headers: _headers, body: jsonEncode(customer.toJson()))
            .timeout(ApiConfig.timeout)
        : await http
            .put(uri, headers: _headers, body: jsonEncode(customer.toJson()))
            .timeout(ApiConfig.timeout);
    _body(response);
    await load(_token, includeInactive: true);
  }

  Future<void> setActive(Customer customer, bool active) async {
    _body(await http
        .patch(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/customers/${customer.id}/status'),
            headers: _headers,
            body: jsonEncode({'active': active}))
        .timeout(ApiConfig.timeout));
    await load(_token, includeInactive: true);
  }

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
