import 'package:america_hub/features/safety/application/sos_controller.dart';
import 'package:america_hub/features/safety/data/sos_location_source.dart';
import 'package:america_hub/features/safety/domain/sos_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sos.dart';

void main() {
  late FakeSosRepository repository;

  SosController controllerWith(SosLocationResult location) {
    repository = FakeSosRepository();
    return SosController(
      repository: repository,
      locationSource: FakeSosLocationSource(location),
    );
  }

  test('konum paylaşılmadığında cihazdan konum hiç istenmez', () async {
    repository = FakeSosRepository();
    final source = FakeSosLocationSource(
      const SosLocationResult(
        SosLocationOutcome.taken,
        SosPoint(latitude: 40.7, longitude: -74.0),
      ),
    );
    final controller = SosController(
      repository: repository,
      locationSource: source,
    );

    await controller.trigger(kind: SosKind.medical, shareLocation: false);

    expect(source.calls, 0);
    expect(repository.sent.single.point, isNull);
    expect(repository.sent.single.toJson().containsKey('latitude'), isFalse);
    controller.dispose();
  });

  test('konum alınamazsa çağrı yine de gider', () async {
    final controller = controllerWith(
      const SosLocationResult(SosLocationOutcome.permissionDenied),
    );

    final sent = await controller.trigger(
      kind: SosKind.personalSafety,
      shareLocation: true,
      locationNote: 'Kat 3, arka giriş',
    );

    // Yardım isteyen birini cihaz ayarına takılıp bekletmek, hiç yardım
    // etmemektir: çağrı gider, konumsuz olduğu ayrıca söylenir.
    expect(sent, isTrue);
    expect(controller.alert, isNotNull);
    expect(controller.alert!.locationShared, isFalse);
    expect(controller.errorMessage, isNull);
    expect(controller.locationNotice, isNotNull);
    controller.dispose();
  });

  test('konum alındığında çağrıya iliştirilir', () async {
    final controller = controllerWith(
      const SosLocationResult(
        SosLocationOutcome.taken,
        SosPoint(latitude: 40.7128, longitude: -74.0060, accuracyMeters: 12),
      ),
    );

    await controller.trigger(kind: SosKind.accident, shareLocation: true);

    expect(repository.sent.single.toJson(), containsPair('latitude', 40.7128));
    expect(repository.sent.single.toJson(), containsPair('accuracyMeters', 12));
    expect(controller.locationNotice, isNull);
    controller.dispose();
  });

  test('aynı çağrıyı tekrar göndermek ikinci bir kart açmaz', () async {
    final controller = controllerWith(
      const SosLocationResult(SosLocationOutcome.unavailable),
    );

    await controller.trigger(kind: SosKind.other, shareLocation: false);
    final first = controller.alert!.id;
    await controller.trigger(kind: SosKind.other, shareLocation: false);

    // Panik düğmesine bir kez basılmaz.
    expect(controller.alert!.id, first);
    controller.dispose();
  });

  test('geri almak açık çağrıyı ekrandan da kaldırır', () async {
    final controller = controllerWith(
      const SosLocationResult(SosLocationOutcome.unavailable),
    );
    await controller.trigger(kind: SosKind.harassment, shareLocation: false);

    expect(await controller.cancel(), isTrue);
    expect(controller.alert, isNull);
    expect(repository.current, isNull);
    controller.dispose();
  });

  test('gönderilemeyen çağrı hata olarak görünür, sessizce yutulmaz', () async {
    final controller = controllerWith(
      const SosLocationResult(SosLocationOutcome.unavailable),
    );
    repository.failOnTrigger = true;

    final sent = await controller.trigger(
      kind: SosKind.medical,
      shareLocation: false,
    );

    expect(sent, isFalse);
    expect(controller.alert, isNull);
    expect(controller.errorMessage, contains('911'));
    controller.dispose();
  });
}
