import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/features/support/application/support_controller.dart';
import 'package:america_hub/features/support/data/support_repository.dart';
import 'package:america_hub/features/support/domain/support_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_support.dart';
import 'support/shell_harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Çekmecenin en altındaki satır: ekrana getirmeden dokunmak testin kendi
/// kusuru olur, ekranın değil.
Future<void> openSupport(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await settle(tester);
  await tester.dragUntilVisible(
    find.text('Yardım & Destek'),
    find.byType(ListView).last,
    const Offset(0, -120),
  );
  await settle(tester);
  await tester.tap(find.text('Yardım & Destek').last);
  await settle(tester);
}

void main() {
  test('liste alınamadığında hata tutulur, boş liste gösterilmez', () async {
    final repository = FakeSupportRepository()
      ..listFailure = const ApiException(message: 'Sunucuya ulaşılamadı.');
    final controller = SupportController(repository: repository);

    await controller.load();

    // Açtığı talebi ekranda göremeyen üye onun kaybolduğunu düşünür: hata
    // ayrı bir alanda duruyor ve ekran önce ona bakıyor.
    expect(controller.listError, 'Sunucuya ulaşılamadı.');
    expect(controller.requests, isEmpty);
    controller.dispose();
  });

  test('açık talep sınırı ayrı bir cümleyle söylenir', () async {
    final controller = SupportController(
      repository: _RejectingRepository(
        const ApiException(
          message: 'Too many open requests.',
          statusCode: 409,
          code: 'SUPPORT_TOO_MANY_OPEN',
        ),
      ),
    );

    final sent = await controller.submit(
      topic: SupportTopic.account,
      subject: 'Giriş yapamıyorum',
      body: 'Şifre sıfırlama e-postası gelmiyor.',
    );

    expect(sent, isFalse);
    expect(controller.tooManyOpen, isTrue);
    expect(controller.formError, contains('beş açık talebin'));
    controller.dispose();
  });

  test('kapanmış talebe yazılamaz ve sebebi söylenir', () async {
    final repository = FakeSupportRepository();
    final controller = SupportController(repository: repository);
    await repository.create(
      const SupportRequestDraft(
        topic: SupportTopic.content,
        subject: 'Paylaşımım kaldırıldı',
        body: 'Karara itiraz ediyorum.',
        clientToken: 'token-1',
      ),
    );
    repository.answer('talep-1', 'İnceledik, karar yerinde.', close: true);

    final sent = await controller.reply('talep-1', 'Peki neden?');

    expect(sent, isFalse);
    expect(controller.threadError, contains('yeni bir talep aç'));
    controller.dispose();
  });

  test('aynı taslak iki kez gönderilse de tek talep açılır', () async {
    final repository = FakeSupportRepository();
    const draft = SupportRequestDraft(
      topic: SupportTopic.technical,
      subject: 'Uygulama kapanıyor',
      body: 'Çarşı sekmesine girince kapanıyor.',
      clientToken: 'token-1',
    );

    await repository.create(draft);
    await repository.create(draft);

    expect(repository.items, hasLength(1));
  });

  testWidgets('çekmecedeki Yardım & Destek artık bir ekrana gidiyor', (
    tester,
  ) async {
    final repository = FakeSupportRepository();
    await pumpShell(tester, supportRepository: repository);

    await openSupport(tester);

    // Menüdeki satır aylarca "yakında" etiketiyle hiçbir yere gitmiyordu.
    expect(find.text('Sık sorulanlar'), findsOneWidget);
    expect(find.text('Destek taleplerin'), findsOneWidget);
    expect(find.text('Henüz destek talebin yok.'), findsOneWidget);
  });

  testWidgets('liste alınamadığında ekran bunu söyler', (tester) async {
    final repository = FakeSupportRepository()
      ..listFailure = const ApiException(message: 'Sunucuya ulaşılamadı.');
    await pumpShell(tester, supportRepository: repository);

    await openSupport(tester);

    expect(find.text('Talep listen alınamadı'), findsOneWidget);
    expect(find.textContaining('talebin olmadığı anlamına gelmez'), findsOneWidget);
    expect(find.text('Henüz destek talebin yok.'), findsNothing);
  });
}

class _RejectingRepository implements SupportRepository {
  _RejectingRepository(this.failure);

  final Object failure;

  @override
  Future<String> create(SupportRequestDraft draft) async => throw failure;

  @override
  Future<List<SupportRequest>> list() async => const [];

  @override
  Future<void> reply(String id, String body) async => throw failure;

  @override
  Future<SupportRequest> thread(String id) async => throw failure;
}
