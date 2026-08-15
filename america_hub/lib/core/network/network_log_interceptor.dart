import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'app_environment.dart';

/// Geliştirme derlemesinde her isteğin ne olduğunu ve ne döndüğünü yazar.
///
/// `AppEnvironmentConfig.allowNetworkLogging` baştan beri vardı ama hiçbir yerde
/// kullanılmıyordu: uygulama hiçbir derlemede tek bir ağ satırı bile
/// yazmıyordu. Bir ekran "yüklenemedi" dediğinde bunun oturumdan mı, boş
/// veriden mi, yoksa düşen bir servisten mi geldiğini anlamanın yolu yoktu.
///
/// Yazılan şey bilerek dar: yöntem, yol, durum kodu ve sunucunun hata kodu.
/// Başlıklar ve gövdeler yazılmıyor - `Authorization` başlığı jetonu, giriş
/// gövdesi şifreyi taşır ve ikisinin de cihaz günlüğüne düşmesi kabul edilemez.
/// Üretim derlemesinde satırın tamamı devre dışı.
class NetworkLogInterceptor extends Interceptor {
  const NetworkLogInterceptor();

  static bool get enabled => AppEnvironmentConfig.allowNetworkLogging;

  // debugPrint, developer.log değil: ikincisi yalnızca DevTools'un günlük
  // sekmesine düşüyor, konsola ve logcat'e hiç çıkmıyor - yani terminalden
  // bakan biri için hiç yazılmamış oluyor.
  void _log(String message) => debugPrint('[ağ] $message');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) _log('→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled) {
      _log(
        '← ${response.statusCode} ${response.requestOptions.method} '
        '${response.requestOptions.uri.path}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    if (enabled) {
      final status = error.response?.statusCode;
      // Sunucunun kendi hata kodu ("NEWS_UNAVAILABLE" gibi) neyin yanlış
      // gittiğini durum kodundan daha iyi anlatıyor; mesaj metni zaten
      // ekranda görünüyor, burada tekrarına gerek yok.
      final data = error.response?.data;
      final code = data is Map && data['error'] is Map
          ? data['error']['code']
          : null;
      _log(
        '✗ ${status ?? error.type.name} ${error.requestOptions.method} '
        '${error.requestOptions.uri.path}'
        '${code != null ? ' ($code)' : ''}',
      );
    }
    handler.next(error);
  }
}
