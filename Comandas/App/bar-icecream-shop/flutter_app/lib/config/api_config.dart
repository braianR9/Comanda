// URL y API Key llegan al compilar, desde config/local.json (no versionado):
//   flutter run --dart-define-from-file=config/local.json
// Ver config/local.example.json.
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://localhost:5001');

class ApiConfig {
  static const String baseUrl = kApiBaseUrl;
  static const String loginEndpoint = '/api/Auth/login';
  static String uploadImageEndpoint(int empresaId) =>
      '/api/empresas/$empresaId/imagen';
  static const Duration timeout = Duration(seconds: 15);

  // API Key requerida en todas las requests
  static const String apiKeyHeader = 'focoKey';
  static const String apiKeyValue = String.fromEnvironment('API_KEY');

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        apiKeyHeader: apiKeyValue,
      };
}
