import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ClientDiagnostics {
  ClientDiagnostics._();
  static String? token;
  static String? ownerToken;
  static bool _sending = false;
  static DateTime? _lastSent;
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(report(details.exceptionAsString(), details.stack?.toString(),
          details.library));
    };
    final previousPlatform = WidgetsBinding.instance.platformDispatcher.onError;
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      unawaited(report(error.toString(), stack.toString(), 'Dart'));
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  static Future<void> report(
      String message, String? stack, String? library) async {
    final auth = ownerToken ?? token;
    if (auth == null ||
        _sending ||
        (_lastSent != null &&
            DateTime.now().difference(_lastSent!) <
                const Duration(seconds: 5))) {
      return;
    }
    _sending = true;
    _lastSent = DateTime.now();
    final client = http.Client();
    try {
      await client
          .post(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/${ownerToken != null ? 'system' : 'diagnostics'}/client-error'),
            headers: {...ApiConfig.headers, 'Authorization': 'Bearer $auth'},
            body: jsonEncode({
              'message': _cut(message, 4000),
              'stack': _cut(stack, 12000),
              'library': _cut(library, 150)
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      /* El reporte de errores no debe generar otro error. */
    } finally {
      client.close();
      _sending = false;
    }
  }

  static String? _cut(String? value, int max) =>
      value == null || value.length <= max ? value : value.substring(0, max);
}
