enum AppEnvironment { development, staging, production }

abstract final class AppEnvironmentConfig {
  static const _raw = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static AppEnvironment get current => switch (_raw) {
    'production' => AppEnvironment.production,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.development,
  };

  static bool get allowNetworkLogging => current == AppEnvironment.development;
}
