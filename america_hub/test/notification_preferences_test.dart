import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/features/notifications/application/notifications_controller.dart';
import 'package:america_hub/features/notifications/domain/entities/app_notification.dart';
import 'package:america_hub/features/notifications/domain/entities/notification_preference.dart';
import 'package:america_hub/features/notifications/domain/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Sunucu yerine bellek. Sunucunun iki kuralını taklit ediyor: yalnızca
/// gönderilen tür değişiyor ve cevap her zaman kaydedilmiş son hâl.
class _FakePreferences implements NotificationRepository {
  _FakePreferences({this.readFailure, this.writeFailure});

  final ApiException? readFailure;
  final ApiException? writeFailure;
  final Map<String, bool> stored = {};
  final List<Map<String, bool>> writes = [];

  @override
  Future<List<AppNotification>> getNotifications() async => const [];

  @override
  Future<void> markAllRead() async {}

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<NotificationPreferences> getPreferences() async {
    if (readFailure != null) throw readFailure!;
    return _snapshot();
  }

  @override
  Future<NotificationPreferences> savePreferences(Map<String, bool> changes) async {
    writes.add(changes);
    if (writeFailure != null) throw writeFailure!;
    stored.addAll(changes);
    return _snapshot();
  }

  NotificationPreferences _snapshot() {
    final values = <NotificationPreferenceKind, bool>{};
    for (final kind in NotificationPreferenceKind.values) {
      values[kind] = stored[kind.wire] ?? true;
    }
    return NotificationPreferences(values);
  }
}

/// Çekmecenin altındaki satır: ekrana getirmeden dokunmak testin kendi kusuru
/// olur, ekranın değil.
Future<void> openPreferences(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await settle(tester);
  await tester.dragUntilVisible(
    find.text('Bildirim Tercihleri'),
    find.byType(ListView).last,
    const Offset(0, -120),
  );
  await settle(tester);
  await tester.tap(find.text('Bildirim Tercihleri').last);
  await settle(tester);
}

void main() {
  test('okunamayan tercih hepsi açık gösterilmez', () async {
    final controller = NotificationsController(
      repository: _FakePreferences(
        readFailure: const ApiException(message: 'Sunucuya ulaşılamadı.'),
      ),
    );

    await controller.loadPreferences();

    // `null` "hepsi açık" değil "okunmadı" demek; ekran ikisini ayırt edebilsin
    // diye tercihler boş kalıyor ve sebep ayrı alanda duruyor.
    expect(controller.preferences, isNull);
    expect(controller.preferencesError, contains('Sunucuya ulaşılamadı.'));
    controller.dispose();
  });

  test('yalnızca değişen tür gönderilir', () async {
    final repository = _FakePreferences();
    final controller = NotificationsController(repository: repository);
    await controller.loadPreferences();

    final saved = await controller.setPreference(
      NotificationPreferenceKind.postLike,
      false,
    );

    expect(saved, isTrue);
    expect(repository.writes.single, {'post_like': false});
    expect(controller.preferences!.isEnabled(NotificationPreferenceKind.postLike), isFalse);
    // Dokunulmayan tür sunucuda da ekranda da açık kaldı.
    expect(controller.preferences!.isEnabled(NotificationPreferenceKind.postComment), isTrue);
    expect(controller.preferences!.mutedCount, 1);
    controller.dispose();
  });

  test('sunucu kabul etmezse anahtar eski hâline döner', () async {
    final controller = NotificationsController(
      repository: _FakePreferences(
        writeFailure: const ApiException(message: 'Kaydedilemedi.', statusCode: 500),
      ),
    );
    await controller.loadPreferences();

    final saved = await controller.setPreference(
      NotificationPreferenceKind.friendRequest,
      false,
    );

    // Kapattığını sanıp bildirim almaya devam etmek, sessizce geri alınan bir
    // ayarın bedeli. Anahtar geri dönüyor ve sebebi ekranda yazıyor.
    expect(saved, isFalse);
    expect(controller.preferences!.isEnabled(NotificationPreferenceKind.friendRequest), isTrue);
    expect(controller.preferencesError, contains('Kaydedilemedi.'));
    controller.dispose();
  });

  testWidgets('çekmecedeki satır ekranı açıyor', (tester) async {
    await pumpShell(tester, notifications: _FakePreferences());
    await openPreferences(tester);

    expect(find.text('Gönderime yorum'), findsOneWidget);
    expect(find.text('Arkadaşlık istekleri'), findsOneWidget);
    // Olmayan bir push ayarı vaat etmiyoruz.
    expect(
      find.textContaining('anlık bildirim ya da e-posta göndermiyor'),
      findsOneWidget,
    );
    // Kapatılamayan iki tür sebebiyle birlikte yazıyor - listenin altında, o
    // yüzden görünür hâle getirmeden aranmıyor.
    await tester.dragUntilVisible(
      find.text('Kapatılamayan iki bildirim'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    expect(find.text('Kapatılamayan iki bildirim'), findsOneWidget);
  });

  testWidgets('anahtar kapatılınca sunucuya tek tür gidiyor', (tester) async {
    final repository = _FakePreferences();
    await pumpShell(tester, notifications: repository);
    await openPreferences(tester);

    await tester.tap(find.byType(Switch).first);
    await settle(tester);

    expect(repository.writes.single, {'post_comment': false});
    await tester.dragUntilVisible(
      find.textContaining('1 tür kapalı'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    expect(find.textContaining('1 tür kapalı'), findsOneWidget);
  });
}
