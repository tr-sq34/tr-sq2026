abstract interface class SessionExpiryHandler {
  Future<void> onSessionExpired();
}
