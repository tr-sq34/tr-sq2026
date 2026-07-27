abstract final class ApiConfig {
  /// Override per environment with --dart-define=API_BASE_URL=https://api.example.com/v1.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.turksquare.com/v1',
  );

  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 20);
}
