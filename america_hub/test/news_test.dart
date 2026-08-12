import 'package:america_hub/features/community/application/community_comments_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_content_moderation_repository.dart';
import 'package:america_hub/features/news/application/news_controller.dart';
import 'package:america_hub/features/news/data/repositories/mock_news_comments_repository.dart';
import 'package:america_hub/features/news/data/repositories/mock_news_repository.dart';
import 'package:america_hub/features/news/domain/entities/news_article.dart';
import 'package:america_hub/features/news/presentation/screens/news_center_screen.dart';
import 'package:america_hub/features/news/presentation/widgets/headline_strip.dart';
import 'package:america_hub/features/news/presentation/widgets/news_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_image_http.dart';
import 'support/shell_harness.dart';

/// Haber Merkezi'ni mock veriyle ekrana koyar.
///
/// Denetleyici testler arasında paylaşılmıyor: beğeni sayacı denetleyicide
/// tutulduğu için paylaşılan bir örnek, bir testin bıraktığı tepkiyi diğerine
/// taşırdı.
Future<NewsController> pumpNewsCenter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  installFakeImageHttp();

  final controller = NewsController(repository: MockNewsRepository());
  await tester.pumpWidget(
    MaterialApp(
      home: NewsCenterScreen(
        controller: controller,
        commentsController: CommunityCommentsController(
          repository: MockNewsCommentsRepository(viewer: () => null),
        ),
        moderationRepository: MockContentModerationRepository(),
        viewerId: 'local-user',
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('the news centre lists what the repository publishes', (
    tester,
  ) async {
    await pumpNewsCenter(tester);

    // Liste tembel kurulur; ekrana sığan kadarı çizilir, hepsi değil.
    expect(find.byType(NewsCard), findsWidgets);
    expect(
      find.textContaining('USCIS, çalışma izni uzatma sürelerini'),
      findsOneWidget,
    );
    expect(
      find.textContaining("NYC Türkevi'nde Türk el sanatları"),
      findsOneWidget,
    );
  });

  testWidgets('a category chip narrows the list to that category', (
    tester,
  ) async {
    await pumpNewsCenter(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Göçmenlik'));
    await tester.pump();

    expect(find.byType(NewsCard), findsOneWidget);
    expect(
      find.textContaining('USCIS, çalışma izni uzatma sürelerini'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a headline opens the article body', (tester) async {
    await pumpNewsCenter(tester);

    await tester.tap(find.byType(NewsCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Gövde yalnızca detayda gelir; listede yoktu.
    expect(find.textContaining('otomatik uzatma'), findsWidgets);
    expect(find.text('Yorumlar (1)'), findsOneWidget);
  });

  testWidgets('liking an article moves the counter and taking it back undoes '
      'it', (tester) async {
    await pumpNewsCenter(tester);

    await tester.tap(find.byType(NewsCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('34'), findsOneWidget);
    await tester.tap(find.text('34'));
    await tester.pump();
    expect(find.text('35'), findsOneWidget);

    // İkinci dokunuş tepkiyi geri alır: sunucudaki birincil anahtar da kişi
    // başına tek tepki diyor.
    await tester.tap(find.text('35'));
    await tester.pump();
    expect(find.text('34'), findsOneWidget);
  });

  testWidgets('a news comment is written with the feed\'s own editor', (
    tester,
  ) async {
    await pumpNewsCenter(tester);

    await tester.tap(find.byType(NewsCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Yorumlar (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Akıştaki yorum sayfasının ta kendisi — kopyası değil.
    expect(find.text('Bu haber hakkında ne düşünüyorsun?'), findsOneWidget);
    expect(
      find.text('Başvurum beklemede, 540 gün haberi çok işime yaradı.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'Teşekkürler.');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Teşekkürler.'), findsOneWidget);
  });

  testWidgets('the home headline strip carries the published article, not a '
      'fixed list', (tester) async {
    await pumpShell(tester);
    await tester.pump();

    // Şerit ana sayfanın alt yarısında; tembel liste onu görünene kadar
    // kurmuyor.
    await tester.scrollUntilVisible(
      find.text("AMERİKA'DAN MANŞETLER"),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    // Şerit artık depodan besleniyor: manşet sırası 1 olan haber hem büyük
    // kartta hem küçük resim şeridinde aynı başlığı taşıyor.
    expect(
      find.textContaining('USCIS, çalışma izni uzatma sürelerini'),
      findsWidgets,
    );
  });

  testWidgets('the strip hands the tapped headline to the shell', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = NewsController(repository: MockNewsRepository());
    NewsArticle? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeadlineStrip(
            controller: controller,
            onOpenArticle: (article) => opened = article,
            onOpenNewsCenter: () {},
          ),
        ),
      ),
    );
    // Manşet gelmeden şerit hiç çizilmez: boş bir kutu göstermek, olmayan bir
    // yayını varmış gibi sunmak olurdu.
    expect(find.byType(InkWell), findsNothing);

    await controller.loadHeadlines();
    await tester.pump();
    // İlki büyük kartın başlığı, ikincisi altındaki küçük resim şeridi.
    await tester.tap(find.textContaining('USCIS, çalışma izni uzatma').first);
    await tester.pump();

    expect(opened?.id, 'news-uscis');
  });

  testWidgets('the drawer opens the news centre', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Haber Merkezi').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NewsCenterScreen), findsOneWidget);
    expect(find.byType(NewsCard), findsWidgets);
  });
}
