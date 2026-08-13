import 'package:america_hub/core/widgets/app_remote_image.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_content_moderation_repository.dart';
import 'package:america_hub/features/community/presentation/screens/story_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_image_http.dart';

Future<StoryController> _loadedController() async {
  final controller = StoryController(repository: MockCommunityRepository());
  await controller.load();
  return controller;
}

/// Sayfa geçişini bitirir.
///
/// `pumpAndSettle` burada kullanılamıyor: slayt sayacı bir dakika boyunca kare
/// istiyor, yani ekran hiç "durulmuyor".
Future<void> _settlePage(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _viewer(StoryController controller) => MaterialApp(
  home: StoryViewerScreen(
    controller: controller,
    initialStoryId: controller.items.first.id,
    moderationRepository: MockContentModerationRepository(),
  ),
);

void main() {
  // Slaytlar kendiliğinden geçmiyordu: görüntüleyicide hiç zamanlayıcı yoktu,
  // ilerlemek için parmakla kaydırmak gerekiyordu.
  testWidgets('a slide hands over to the next one after a minute', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = await _loadedController();
    await tester.pumpWidget(_viewer(controller));
    await tester.pump();

    expect(find.text('Elif Demir'), findsOneWidget);

    // Bir dakika dolmadan yerinde duruyor.
    await tester.pump(const Duration(seconds: 55));
    expect(find.text('Elif Demir'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mert Kaya'), findsOneWidget);
  });

  testWidgets('the right half moves forward, the left half moves back', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = await _loadedController();
    await tester.pumpWidget(_viewer(controller));
    await tester.pump();

    final size = tester.getSize(find.byType(StoryViewerScreen));
    await tester.tapAt(Offset(size.width * .8, size.height * .5));
    await _settlePage(tester);
    expect(find.text('Mert Kaya'), findsOneWidget);

    await tester.tapAt(Offset(size.width * .1, size.height * .5));
    await _settlePage(tester);
    expect(find.text('Elif Demir'), findsOneWidget);
  });

  // "Yanıt yaz" yalnızca bir bilgi kutusu gösteriyordu; oysa depoda yanıt ucu
  // baştan beri vardı.
  testWidgets('a reply goes through the repository instead of a notice', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = await _loadedController();
    await tester.pumpWidget(_viewer(controller));
    await tester.pump();

    await tester.tap(find.text('Yanıt yaz'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Fotoğraf çok güzel.');
    await tester.pump();
    await tester.tap(find.text('Gönder'));
    await _settlePage(tester);

    expect(find.text('Yanıtın Elif Demir kişisine gönderildi.'), findsOneWidget);
  });

  testWidgets('an empty reply cannot be sent', (tester) async {
    installFakeImageHttp();
    final controller = await _loadedController();
    await tester.pumpWidget(_viewer(controller));
    await tester.pump();

    await tester.tap(find.text('Yanıt yaz'));
    await tester.pumpAndSettle();

    final send = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Gönder'), matching: find.byType(FilledButton)),
    );
    expect(send.onPressed, isNull);
  });

  // Yerel bir dosya yolu da bir görsel: yükleme bitene kadar elimizde
  // yalnızca o var, eskiden bu yollar boş bir kareye dönüşüyordu.
  testWidgets('AppRemoteImage draws a local file path as an image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: AppRemoteImage(
            imageUrl: '/storage/emulated/0/DCIM/kare.jpg',
            semanticLabel: 'Seçilen fotoğraf',
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('AppRemoteImage keeps the placeholder for an unusable source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: AppRemoteImage(imageUrl: '   ', semanticLabel: 'Boş'),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
  });
}
