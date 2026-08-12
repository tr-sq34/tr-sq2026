import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/presentation/widgets/story_composer_sheet.dart';
import 'package:america_hub/features/promotions/application/promotions_controller.dart';
import 'package:america_hub/features/promotions/data/repositories/mock_promotion_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _composer() => MaterialApp(
  home: Scaffold(
    body: StoryComposerSheet(
      storyController: StoryController(repository: MockCommunityRepository()),
      mediaUploadController: MediaUploadController(
        repository: MockMediaUploadRepository(),
      ),
      promotionsController: PromotionsController(
        repository: MockPromotionRepository(),
      ),
    ),
  ),
);

void main() {
  // Duzenleyici saydam arka planli bir sayfa olarak aciliyor. Kendi zeminini
  // cizmezse arkadaki akis formun icinden gorunuyor - ekranin bir kez
  // yasadigi hata buydu. Yuzeyin donuk oldugunu burada tutuyoruz.
  testWidgets('the composer paints its own opaque surface', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_composer());
    await tester.pump();

    // Agactaki ilk Container gövdenin kendisi; sayfanin zemini o.
    final root = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(StoryComposerSheet),
            matching: find.byType(Container),
          )
          .first,
    );

    expect((root.decoration as BoxDecoration).color?.a, 1.0);
  });

  // Gorsel secilmeden Story paylasilamaz: guvenlik kontrolu bir gorsel
  // uzerinde calisiyor, olmayan bir karenin kontrolu de olmuyor.
  testWidgets('sharing stays closed until a photo is attached', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_composer());
    await tester.pump();

    await tester.ensureVisible(find.text('Story paylaş'));
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Story paylaş'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
