import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_config.dart';
import '../storage/token_store.dart';
import 'crash_reporter.dart';

/// Telemetrinin platforma dokunan yarısı.
///
/// [CrashReporter] bilerek saf: ne eklenti çağırıyor ne de ağ tanıyor, bu
/// yüzden testte olduğu gibi çalışıyor. Cihaz bilgisini toplamak ve isteği
/// göndermek burada.

/// Çökme raporunu taşıyan Dio, uygulamanın geri kalanının kullandığı
/// [ApiClient] değil ve olamaz.
///
/// Sebebi bir hafta önce ayıkladığımız hatanın ta kendisi: `AuthInterceptor`,
/// kimlikli bir istekten 401 dönerse jeton deposunu siliyor ve üyeyi oturumdan
/// atıyor. Telemetri ucu bir gün yanlış yapılandırılıp 401 dönerse, çökmeyi
/// bildirmeye çalışan kod üyeyi uygulamadan atmış olurdu — yani gözlem aracı
/// gözlediği hatanın daha kötüsünü üretirdi. Bu Dio'nun hiç denetleyicisi yok;
/// jetonu, varsa, tek seferlik başlık olarak kendisi ekliyor.
TelemetrySender crashTelemetrySender({required TokenStore tokenStore, Dio? dio}) {
  final client = dio ??
      Dio(
        BaseOptions(
          baseUrl: ApiConfig.communityBaseUrl,
          // Kısa: bu istek hiçbir ekranı bekletmiyor, başarısız olması da
          // önemli değil. Uzun bir zaman aşımı sadece çöken bir uygulamanın
          // kapanmasını geciktirir.
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: const {'Accept': 'application/json'},
        ),
      );

  return (path, body) async {
    final token = await tokenStore.readAccessToken();
    await client.post<dynamic>(
      path,
      data: body,
      options: Options(
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
        // Sunucu 202 dönüyor; başka bir şey dönerse de bu isteği yapan kod
        // zaten hiçbir şey yapmıyor. Hata fırlatmasın diye tüm durumlar kabul.
        validateStatus: (_) => true,
      ),
    );
  };
}

/// Cihaz, işletim sistemi ve sürüm. Hepsi isteğe bağlı: eklenti yanıt vermezse
/// rapor eksik alanla gider, hiç gitmemesindense.
Future<AppBuildInfo> discoverBuildInfo() async {
  final version = await _appVersion();
  if (kIsWeb) return AppBuildInfo(platform: 'web', appVersion: version);

  try {
    final plugin = DeviceInfoPlugin();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = await plugin.androidInfo;
        return AppBuildInfo(
          platform: 'android',
          appVersion: version,
          osVersion: 'Android ${android.version.release} (SDK ${android.version.sdkInt})',
          deviceModel: '${android.manufacturer} ${android.model}'.trim(),
        );
      case TargetPlatform.iOS:
        final ios = await plugin.iosInfo;
        return AppBuildInfo(
          platform: 'ios',
          appVersion: version,
          osVersion: '${ios.systemName} ${ios.systemVersion}',
          // utsname.machine gerçek modeli veriyor (iPhone15,2); `model` her
          // cihazda "iPhone" yazıyor ve hangi donanımın çöktüğünü söylemiyor.
          deviceModel: ios.utsname.machine,
        );
      default:
        return AppBuildInfo(platform: 'other', appVersion: version);
    }
  } catch (_) {
    return AppBuildInfo(
      platform: defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'other',
      appVersion: version,
    );
  }
}

Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    // Sürüm bilinmiyorsa da rapor gitmeli; panel bunu "bilinmiyor" diye
    // gruplayacak, boş bırakılmış bir alandan iyidir.
    return 'bilinmiyor';
  }
}
