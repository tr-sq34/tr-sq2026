abstract final class ApiConfig {
  /// Must end with `/`: endpoint paths are relative and must retain `/v1/`.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.turksquare.com/v1/',
  );

  /// Community is deliberately a separate service/account. Keeping its base
  /// URL distinct prevents a future Community deployment from being coupled to
  /// the identity service's load balancer or database boundary.
  ///
  /// This is an internal transport address only; it is never displayed in the
  /// application UI. Local development can override it with
  /// `--dart-define=COMMUNITY_API_BASE_URL=http://localhost:.../v1/`.
  static const communityBaseUrl = String.fromEnvironment(
    'COMMUNITY_API_BASE_URL',
    defaultValue: 'https://community-api.turksquare.com/v1/',
  );

  /// Public branded edge for the Verification Vault. It is distinct from
  /// Identity and Community so no sensitive verification traffic shares their
  /// databases or service credentials.
  static const verificationBaseUrl = String.fromEnvironment(
    'VERIFICATION_API_BASE_URL',
    defaultValue: 'https://verify.turksquare.com/v1/',
  );

  /// The messaging gateway. It is the only client of the Matrix homeserver,
  /// which has no public address at all — the app talks to this service and
  /// never learns that Matrix is the transport underneath.
  static const messagingBaseUrl = String.fromEnvironment(
    'MESSAGING_API_BASE_URL',
    defaultValue: 'https://messages-api.turksquare.com/v1/',
  );

  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 20);
}
