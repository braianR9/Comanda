// URL base de la API — cambiá según el entorno
const String kApiBaseUrl = 'http://localhost:5001';

class ApiConfig {
  static const String baseUrl = kApiBaseUrl;
  static const String loginEndpoint = '/api/Auth/login';
  static String uploadImageEndpoint(int empresaId) =>
      '/api/empresas/$empresaId/imagen';
  static const Duration timeout = Duration(seconds: 15);

  // API Key requerida en todas las requests
  static const String apiKeyHeader = 'focoKey';
  static const String apiKeyValue = 'dfjgkhkpuioyturtyerywer&%\$#@';

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        apiKeyHeader: apiKeyValue,
      };
}
