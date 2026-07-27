import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'api_config.dart';

/// Makes concurrent expired-token requests share one refresh operation. Refresh
/// calls use a dedicated Dio instance, so the auth interceptor can never
/// recursively intercept its own refresh request.
class TokenRefreshCoordinator {
  TokenRefreshCoordinator({required TokenStore tokenStore, Dio? refreshDio})
    : _tokenStore = tokenStore,
      _refreshDio =
          refreshDio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              headers: const {'Accept': 'application/json'},
            ),
          );

  final TokenStore _tokenStore;
  final Dio _refreshDio;
  Future<bool>? _inFlight;

  Future<bool> refresh() => _inFlight ??= _refresh().whenComplete(() {
    _inFlight = null;
  });

  Future<bool> _refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final payload = response.data?['data'];
      if (payload is! Map) return false;
      final accessToken = payload['accessToken'];
      final replacement = payload['refreshToken'];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          replacement is! String ||
          replacement.isEmpty) {
        return false;
      }
      await _tokenStore.save(
        accessToken: accessToken,
        refreshToken: replacement,
      );
      return true;
    } on DioException {
      return false;
    }
  }
}
