import 'package:geolocator/geolocator.dart';

import '../domain/sos_alert.dart';

enum SosLocationOutcome {
  taken,

  /// Cihazın konum servisi kapalı.
  serviceDisabled,

  /// Üye izin vermedi ya da kalıcı olarak reddetti.
  permissionDenied,

  /// İzin var ama nokta gelmedi (kapalı alan, zaman aşımı).
  unavailable,
}

class SosLocationResult {
  const SosLocationResult(this.outcome, [this.point]);

  final SosLocationOutcome outcome;
  final SosPoint? point;

  String? get message => switch (outcome) {
    SosLocationOutcome.taken => null,
    SosLocationOutcome.serviceDisabled =>
      'Cihazın konum servisi kapalı. Çağrı konumsuz gidecek; nerede olduğunu aşağıya yazabilirsin.',
    SosLocationOutcome.permissionDenied =>
      'Konum izni verilmedi. Çağrı konumsuz gidecek; nerede olduğunu aşağıya yazabilirsin.',
    SosLocationOutcome.unavailable =>
      'Konum alınamadı. Çağrı konumsuz gidecek; nerede olduğunu aşağıya yazabilirsin.',
  };
}

/// Cihazın konum yığınının üstündeki dikiş yeri: SOS ekranı bunun sahtesiyle
/// test edilebilsin diye ayrı duruyor.
abstract interface class SosLocationSource {
  Future<SosLocationResult> take();
}

/// Uygulamanın koordinatı ham hâliyle okuduğu tek yer.
///
/// Onboarding'deki [GeolocatorDeviceLocationSource] noktayı şehir adına çevirip
/// atar — yerleşim, üyenin seçtiği bir tercihtir, sürekli bir iz değil. Burası
/// o kuralın bilerek açılan tek deliği: nokta yalnızca üye yardım istediği anda
/// alınır, isteğe gider ve uygulamada saklanmaz.
class GeolocatorSosLocationSource implements SosLocationSource {
  const GeolocatorSosLocationSource();

  @override
  Future<SosLocationResult> take() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const SosLocationResult(SosLocationOutcome.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const SosLocationResult(SosLocationOutcome.permissionDenied);
      }

      // Yardım çağrısında şehir yeterli değil: burada istenen doğruluk, bir
      // ekibin kapıyı bulabilmesi. Zaman aşımı kısa — konum beklerken
      // gönderilmeyen bir çağrı, gönderilmemiş bir çağrıdır.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return SosLocationResult(
        SosLocationOutcome.taken,
        SosPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy.isFinite
              ? position.accuracy.round()
              : null,
        ),
      );
    } catch (_) {
      return const SosLocationResult(SosLocationOutcome.unavailable);
    }
  }
}
