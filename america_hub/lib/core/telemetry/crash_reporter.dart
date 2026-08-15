import 'dart:math';

import 'package:flutter/foundation.dart';

/// Uygulama üyenin telefonunda çöktüğünde bunu bilen tek taraf üyenin kendisi.
///
/// Bu dosya o bilgiyi geri getiriyor. Sentry ya da Crashlytics yerine kendi
/// servisimize yazıyor: üçüncü bir tarafa hesap açmak, derlemeye bir DSN
/// gömmek ve üyelerimizin ürettiği her yığın izini bizim işletmediğimiz bir
/// sunucuya göndermek gerekmiyor. Panelin sorduğu soru zaten basit — açılan
/// oturumların kaçı çökmeden bitti.
///
/// Üç kural var:
///
/// 1. Rapor göndermek asla yeni bir hata doğurmaz. Buradaki her yol
///    yutuluyor; çökmeyi bildirmeye çalışırken çökmek, hiç bildirmemekten
///    kötüdür.
/// 2. Aynı hata sonsuz kez gönderilmez. Bir çizim hatası saniyede yüzlerce
///    kez tekrar edebilir; oturum başına sayı sınırlı ve tekrar edenler
///    eleniyor.
/// 3. Gönderilen şey dar: hatanın türü, mesajı, yığın izi ve açık olan ekran.
///    Kimlik jetonu isteğe bağlı olarak gidiyor ki destek "bu üyenin
///    uygulaması neden çöküyor" sorusunu yanıtlayabilsin; sunucu mesajı ve
///    yığını yazmadan önce e-posta, jeton ve imza gibi kalıpları temizliyor.
typedef TelemetrySender = Future<void> Function(String path, Map<String, dynamic> body);

/// Cihaz ve sürüm bilgisi. Ayrı bir tür, çünkü bunları toplayan eklentiler
/// platform kanalı istiyor ve test ortamında yok; denetleyici bunu dışarıdan
/// alınca sınanabilir kalıyor.
@immutable
class AppBuildInfo {
  const AppBuildInfo({
    required this.platform,
    required this.appVersion,
    this.osVersion,
    this.deviceModel,
  });

  /// Sunucunun kabul ettiği dört değerden biri: android, ios, web, other.
  final String platform;
  final String appVersion;
  final String? osVersion;
  final String? deviceModel;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'appVersion': appVersion,
    if (osVersion != null) 'osVersion': osVersion,
    if (deviceModel != null) 'deviceModel': deviceModel,
  };
}

class CrashReporter {
  CrashReporter({required TelemetrySender send, this.maxReportsPerSession = 8})
    : _send = send,
      sessionId = _uuidV4();

  /// Küresel hata kancaları (FlutterError.onError, PlatformDispatcher.onError)
  /// statik olmak zorunda; bunlara verilecek denetleyicinin de erişilebilir
  /// olması gerekiyor. Uygulamanın geri kalanındaki açık bağımlılık geçişinden
  /// sapan tek yer burası ve sebebi bu.
  static CrashReporter? instance;

  final TelemetrySender _send;
  final int maxReportsPerSession;

  /// Bu açılışın kimliği. Çökme raporu hangi oturuma ait olduğunu ancak kendi
  /// ürettiği bu numarayla söyleyebiliyor.
  final String sessionId;

  AppBuildInfo? _info;
  int _sent = 0;
  final Set<String> _seen = <String>{};

  /// Açık olan ekran. Hatayı devralacak kişi için tek en yararlı alan ve
  /// toplanması en ucuzu.
  String? currentScreen;

  bool get started => _info != null;

  /// Açılışı kaydeder. Bu, panelin paydası: çökme sayısının ölçeği olmadan
  /// "on çökme" ne felaket ne de gürültü olduğu anlaşılmaz.
  Future<void> start(AppBuildInfo info) async {
    _info = info;
    await _post('app/launches', {'sessionId': sessionId, ...info.toJson()});
  }

  void recordFlutterError(FlutterErrorDetails details) {
    recordError(
      details.exception,
      details.stack,
      // Çizim sırasındaki hata ekranı kaybettirmiyor, kırmızı kutuya
      // çeviriyor: sayılmalı ama çökmesiz kullanım oranını düşürmemeli.
      fatal: false,
      context: details.context?.toString(),
    );
  }

  void recordError(Object error, StackTrace? stack, {bool fatal = true, String? context}) {
    // Başlamamış bir denetleyici cihazı da sürümü de bilmiyor; gönderilen
    // rapor hangi sürümde olduğu bilinmeyen bir rapor olurdu.
    final info = _info;
    if (info == null) return;
    if (_sent >= maxReportsPerSession) return;

    final type = error.runtimeType.toString();
    final message = error.toString();
    // Tek bir çizim hatası saniyede yüzlerce kez tekrar edebiliyor. Aynı hata
    // bir kez gönderiliyor; panel zaten kaç oturumu etkilediğini sayıyor.
    final key = '$type|${message.length > 160 ? message.substring(0, 160) : message}';
    if (!_seen.add(key)) return;

    _sent += 1;
    // Ekran adı önce gezinti gözlemcisinden geliyor; o yoksa Flutter'ın hata
    // ayrıntısındaki bağlam ("while building X") en azından nereye bakılacağını
    // söylüyor.
    final where = currentScreen ?? (context == null ? null : _clip(context, 120));
    _post('app/crashes', {
      'sessionId': sessionId,
      ...info.toJson(),
      'fatal': fatal,
      'errorType': type,
      'message': _clip(message, 1000),
      'screen': ?where,
      if (stack != null) 'stack': _clip(stack.toString(), 8000),
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      await _send(path, body);
    } catch (error) {
      // Bilerek yutuluyor. Ağ yoksa ya da uç yanıt vermiyorsa yapılacak doğru
      // şey sessiz kalmak; bunu bildirecek ikinci bir kanal yok.
      if (kDebugMode) debugPrint('[telemetri] gönderilemedi: $path ($error)');
    }
  }

  static String _clip(String value, int max) => value.length <= max ? value : value.substring(0, max);
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}
