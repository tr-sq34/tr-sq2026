import 'package:america_hub/features/promotions/application/promotions_controller.dart';
import 'package:america_hub/features/promotions/data/repositories/mock_promotion_repository.dart';
import 'package:america_hub/features/promotions/domain/entities/promotion.dart';
import 'package:america_hub/features/promotions/domain/repositories/promotion_repository.dart';
import 'package:america_hub/core/state/async_state.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/community/presentation/widgets/story_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

void main() {
  // Ana sayfadaki sponsorlu alanlar bu faza kadar sabit metindi. Buradaki
  // kontrol, ekranda görünenin depodan geldiğini söylüyor: depoda olmayan bir
  // tanıtım ekranda da olmamalı.
  testWidgets('the story rail carries the sponsored slot from the repository', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.pump();

    expect(find.text('Kervan Market'), findsOneWidget);
    expect(find.text('Sponsorlu'), findsWidgets);
  });

  testWidgets('"Sana Özel Öne Çıkanlar" lists the approved featured card', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.pump();

    expect(find.text('Sana Özel Öne Çıkanlar'), findsOneWidget);
    expect(find.text('Amerika’da İlk Yıl'), findsOneWidget);
    // Reddedilmiş talep hiçbir yüzeyde görünmez; yalnızca sahibinin kendi
    // listesinde durur.
    expect(find.text('Anadolu Lokantası'), findsNothing);
  });

  // "Tanıtım Yap" Story akışının içinde duruyor: paylaşılan görsel, talebin de
  // görseli. Üye yalnızca kendi isteyebileceği alanları görür — öne çıkan kart
  // editoryal, panelden yerleştiriliyor.
  testWidgets('the story composer offers only the placements a member may ask '
      'for', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final community = MockCommunityRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryComposerSheet(
            storyController: StoryController(repository: community),
            mediaUploadController: MediaUploadController(
              repository: MockMediaUploadRepository(),
            ),
            promotionsController: PromotionsController(
              repository: MockPromotionRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Story Alanı Sponsorlu'), findsNothing);
    await tester.ensureVisible(find.text('Tanıtım yap'));
    await tester.tap(find.text('Tanıtım yap'));
    await tester.pump();

    expect(find.text('Story Alanı Sponsorlu'), findsOneWidget);
    expect(find.text('Uygulama içi Banner'), findsOneWidget);
    expect(find.text('Öne Çıkan Kart'), findsNothing);
    expect(find.text('Gerekçe'), findsOneWidget);
    // Ödeme yok: bu fazda talep yalnızca değerlendirmeye gidiyor.
    expect(find.textContaining('Ücret alınmaz'), findsOneWidget);
  });

  test('a submitted request waits for a decision instead of going live', () async {
    final controller = PromotionsController(
      repository: MockPromotionRepository(),
    );
    await controller.loadActive();
    final liveBefore = controller.storySlots.length;

    final now = DateTime.now();
    await controller.submit(
      PromotionRequestDraft(
        placement: PromotionPlacement.storySlot,
        title: 'Beşiktaş Kuaför',
        mediaId: 'media-1',
        startsAt: now,
        endsAt: now.add(const Duration(days: 7)),
        note: 'Açılış duyurusu.',
      ),
    );

    final mine = switch (controller.mine) {
      AsyncData<List<Promotion>>(:final value) => value,
      _ => <Promotion>[],
    };
    final submitted = mine.firstWhere((p) => p.title == 'Beşiktaş Kuaför');
    expect(submitted.status, PromotionStatus.pending);
    expect(submitted.requestNote, 'Açılış duyurusu.');

    // Onaylanmadan yayına çıkmaz: kendi kendini onaylayan bir kuyruk kuyruk
    // değildir.
    await controller.loadActive();
    expect(controller.storySlots.length, liveBefore);
  });

  test('an impression is counted once per session, a click every time', () async {
    final repository = _CountingPromotionRepository();
    final controller = PromotionsController(repository: repository);

    controller
      ..recordImpression('promo-kervan')
      ..recordImpression('promo-kervan')
      ..recordClick('promo-kervan')
      ..recordClick('promo-kervan');

    expect(repository.events.where((e) => e.$2 == PromotionEventKind.impression),
        hasLength(1));
    expect(
      repository.events.where((e) => e.$2 == PromotionEventKind.click),
      hasLength(2),
    );
  });
}

class _CountingPromotionRepository implements PromotionRepository {
  final events = <(String, PromotionEventKind)>[];

  @override
  Future<List<Promotion>> fetchActive() async => const [];

  @override
  Future<List<Promotion>> fetchMine() async => const [];

  @override
  Future<void> submit(PromotionRequestDraft draft) async {}

  @override
  Future<void> recordEvent(String promotionId, PromotionEventKind kind) async =>
      events.add((promotionId, kind));
}
