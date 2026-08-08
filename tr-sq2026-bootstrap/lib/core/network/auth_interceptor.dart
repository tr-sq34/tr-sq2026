import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'token_refresh_coordinator.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required TokenStore tokenStore,
    required TokenRefreshCoordinator refreshCoordinator,
    this.onSessionExpired,
  }) : _dio = dio,
       _tokenStore = tokenStore,
       _refreshCoordinator = refreshCoordinator;

  final Dio _dio;
  final TokenStore _tokenStore;
  final TokenRefreshCoordinator _refreshCoordinator;
  final Future<void> Function()? onSessionExpired;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final canRefresh =
        err.response?.statusCode == 401 &&
        options.headers['Authorization'] != null &&
        options.extra['_authRetry'] != true &&
        _isReplaySafe(options);
    if (canRefresh) {
      // Another request may already have completed the shared refresh before
      // this 401 reached the interceptor. Reuse that new access token instead
      // of consuming the newly rotated refresh token a second time.
      final currentToken = await _tokenStore.readAccessToken();
      final failedToken = options.headers['Authorization'];
      final hasNewAccessToken =
          currentToken != null &&
          currentToken.isNotEmpty &&
          failedToken != 'Bearer $currentToken';
      if (hasNewAccessToken &&
          await _retryWithAccessToken(options, currentToken, handler)) {
        return;
      }
      if (await _refreshCoordinator.refresh()) {
        final accessToken = await _tokenStore.readAccessToken();
        if (accessToken != null &&
            accessToken.isNotEmpty &&
            await _retryWithAccessToken(options, accessToken, handler)) {
          return;
        }
      }
    }
    if (err.response?.statusCode == 401 &&
        options.headers['Authorization'] != null) {
      await _tokenStore.clear();
      await onSessionExpired?.call();
    }
    handler.next(err);
  }

  bool _isReplaySafe(RequestOptions options) {
    const safeMethods = {'GET', 'HEAD', 'OPTIONS'};
    return safeMethods.contains(options.method.toUpperCase()) ||
        options.headers.containsKey('Idempotency-Key');
  }

  Future<bool> _retryWithAccessToken(
    RequestOptions options,
    String accessToken,
    ErrorInterceptorHandler handler,
  ) async {
    final retry = options.copyWith(
      headers: Map<String, dynamic>.from(options.headers)
        ..['Authorization'] = 'Bearer $accessToken',
      extra: Map<String, dynamic>.from(options.extra)..['_authRetry'] = true,
    );
    try {
      handler.resolve(await _dio.fetch<dynamic>(retry));
      return true;
    } on DioException catch (retryError) {
      handler.next(retryError);
      return true;
    }
  }
}
