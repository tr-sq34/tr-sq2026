import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'token_refresh_coordinator.dart';

class ApiClient {
  ApiClient({required TokenStore tokenStore, Dio? dio, Future<void> Function()? onSessionExpired})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
                headers: const {'Accept': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      AuthInterceptor(
        dio: _dio,
        tokenStore: tokenStore,
        refreshCoordinator: TokenRefreshCoordinator(tokenStore: tokenStore),
        onSessionExpired: onSessionExpired,
      ),
    );
  }

  final Dio _dio;

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _request(() => _dio.get<T>(path, queryParameters: queryParameters));
  }

  Future<Response<T>> post<T>(String path, {Object? data}) {
    return _request(() => _dio.post<T>(path, data: data));
  }

  Future<Response<T>> put<T>(String path, {Object? data}) => _request(() => _dio.put<T>(path, data: data));
  Future<Response<T>> delete<T>(String path, {Object? data}) => _request(() => _dio.delete<T>(path, data: data));

  Future<Response<T>> _request<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
