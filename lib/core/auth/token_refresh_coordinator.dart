import '../storage/token_store.dart';

class RefreshedTokens {
  const RefreshedTokens({required this.accessToken, this.refreshToken});
  final String accessToken;
  final String? refreshToken;
}

abstract interface class TokenRefresher {
  Future<RefreshedTokens> refresh(String refreshToken);
}

/// Shares one refresh request across concurrent 401 responses.
class TokenRefreshCoordinator {
  TokenRefreshCoordinator({required TokenStore tokenStore, required TokenRefresher refresher})
      : _tokenStore = tokenStore,
        _refresher = refresher;

  final TokenStore _tokenStore;
  final TokenRefresher _refresher;
  Future<String?>? _inFlightRefresh;

  Future<String?> refreshAccessToken() {
    final active = _inFlightRefresh;
    if (active != null) return active;
    final operation = _refresh();
    _inFlightRefresh = operation;
    operation.whenComplete(() => _inFlightRefresh = null);
    return operation;
  }

  Future<String?> _refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final tokens = await _refresher.refresh(refreshToken);
      await _tokenStore.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
      return tokens.accessToken;
    } catch (_) {
      await _tokenStore.clear();
      return null;
    }
  }
}
