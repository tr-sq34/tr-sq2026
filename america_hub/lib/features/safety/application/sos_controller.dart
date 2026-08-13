import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sos_location_source.dart';
import '../data/sos_repository.dart';
import '../domain/sos_alert.dart';

/// Yardım çağrısının denetleyicisi.
///
/// Açık bir çağrı varken ekran kendini yeniliyor: üyenin görmesi gereken iki
/// şey de zamanla değişiyor — çağrının üstlenilip üstlenilmediği ve konumuna
/// şu anda kaç kişinin bakabildiği.
class SosController extends ChangeNotifier {
  SosController({
    required SosRepository repository,
    SosLocationSource locationSource = const GeolocatorSosLocationSource(),
  }) : _repository = repository,
       _locationSource = locationSource;

  static const _refreshInterval = Duration(seconds: 20);

  final SosRepository _repository;
  final SosLocationSource _locationSource;
  Timer? _timer;

  SosAlert? alert;
  bool isLoading = false;
  bool isSending = false;

  /// Çağrı gönderilemediğinde görünen hata. Konum alınamaması hata değil,
  /// [locationNotice] ile ayrı söyleniyor: konumsuz giden bir çağrı yine de
  /// gitmiş bir çağrıdır.
  String? errorMessage;
  String? locationNotice;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      alert = await _repository.active();
      errorMessage = null;
    } catch (_) {
      errorMessage = 'Yardım çağrısı durumu okunamadı.';
    } finally {
      isLoading = false;
      notifyListeners();
      _syncTimer();
    }
  }

  /// Açık çağrı varken sessizce tazeler: yükleniyor göstergesi yakıp söndürmek,
  /// beklerken bakılan bir ekranda bir şeyin bozulduğu izlenimi veriyor.
  Future<void> _refresh() async {
    try {
      alert = await _repository.active();
      notifyListeners();
    } catch (_) {
      // Geçici bir okuma hatası açık çağrıyı ekrandan silmemeli.
    } finally {
      _syncTimer();
    }
  }

  void _syncTimer() {
    final wanted = alert != null;
    if (wanted && _timer == null) {
      _timer = Timer.periodic(_refreshInterval, (_) => unawaited(_refresh()));
    } else if (!wanted) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// [shareLocation] üyenin kararı: konum paylaşmadan da yardım istenebilir.
  /// Konum alınamazsa çağrı yine de gidiyor — yardım isteyen birini cihaz
  /// ayarına takılıp bekletmek, hiç yardım etmemektir.
  Future<bool> trigger({
    required SosKind kind,
    required bool shareLocation,
    String? note,
    String? locationNote,
  }) async {
    isSending = true;
    errorMessage = null;
    locationNotice = null;
    notifyListeners();
    try {
      SosPoint? point;
      if (shareLocation) {
        final result = await _locationSource.take();
        point = result.point;
        locationNotice = result.message;
      }
      await _repository.trigger(
        SosDraft(
          kind: kind,
          note: note,
          point: point,
          locationNote: locationNote,
        ),
      );
      alert = await _repository.active();
      return true;
    } catch (_) {
      errorMessage =
          'Yardım çağrısı gönderilemedi. Bağlantını kontrol et; acil bir tehlike varsa 911\'i ara.';
      return false;
    } finally {
      isSending = false;
      notifyListeners();
      _syncTimer();
    }
  }

  Future<bool> cancel() async {
    final open = alert;
    if (open == null) return false;
    isSending = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.cancel(open.id);
      alert = null;
      locationNotice = null;
      return true;
    } catch (_) {
      errorMessage = 'Çağrı geri alınamadı.';
      return false;
    } finally {
      isSending = false;
      notifyListeners();
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
