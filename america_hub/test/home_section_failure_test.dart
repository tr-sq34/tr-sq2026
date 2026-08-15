import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/forum/application/forum_controller.dart';
import 'package:america_hub/features/forum/domain/entities/forum.dart';
import 'package:america_hub/features/forum/domain/repositories/forum_repository.dart';
import 'package:america_hub/features/forum/presentation/widgets/forum_trending_section.dart';
import 'package:america_hub/features/news/application/news_controller.dart';
import 'package:america_hub/features/news/data/repositories/mock_news_repository.dart';
import 'package:america_hub/features/news/domain/entities/news_article.dart';
import 'package:america_hub/features/news/domain/repositories/news_repository.dart';
import 'package:america_hub/features/news/presentation/widgets/headline_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_image_http.dart';

/// Ana sayfadaki şeritlerin hepsi listesi boş kaldığında kendini gizliyordu ve
/// bunu isteğin başarılı olup olmadığına bakmadan yapıyordu. Sonuç: haber
/// servisi düştüğünde ekranda "haber yok" bile yazmıyor, bölüm hiç olmamış gibi
/// duruyordu. Üyenin gördüğü tek şey eksik bir sayfaydı.
///
/// Bu dosya iki şeyi birden sınıyor: hata varken şerit bir şey söylüyor, hata
/// yokken ve liste gerçekten boşken hâlâ susuyor.

/// Her isteği reddeden depo.
class _BrokenNewsRepository implements NewsRepository {
  @override
  Future<CursorPage<NewsArticle>> fetchNews({String? cursor, int limit = 20, NewsCategory? category}) =>
      Future.error(Exception('offline'));

  @override
  Future<List<NewsArticle>> fetchHeadlines({int limit = 5}) =>
      Future.error(Exception('offline'));

  @override
  Future<NewsArticle> getArticle(String id) => Future.error(Exception('offline'));

  @override
  Future<NewsReactionTally> react(String articleId, NewsReaction? reaction) =>
      Future.error(Exception('offline'));
}

/// Trend konu isteğini reddeden, kalan çağrıları kullanılmadığı için boş geçen
/// depo.
class _BrokenForumRepository implements ForumRepository {
  @override
  Future<List<ForumCategory>> fetchCategories() async => const [];

  @override
  Future<List<ForumTopic>> fetchTrendingTopics({int limit = 5}) =>
      Future.error(Exception('offline'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} bu testte kullanılmıyor');
}

void main() {
  testWidgets('manşet servisi düşünce şerit yok olmuyor, nedenini söylüyor', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = NewsController(repository: _BrokenNewsRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeadlineStrip(
            controller: controller,
            onOpenArticle: (_) {},
            onOpenNewsCenter: () {},
          ),
        ),
      ),
    );

    await controller.loadHeadlines();
    await tester.pump();

    expect(find.text('Manşetler'), findsOneWidget);
    expect(find.text('Manşetler yüklenemedi.'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
  });

  testWidgets('manşetler geldiğinde uyarı satırı yerini habere bırakıyor', (
    tester,
  ) async {
    installFakeImageHttp();
    final controller = NewsController(repository: MockNewsRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeadlineStrip(
            controller: controller,
            onOpenArticle: (_) {},
            onOpenNewsCenter: () {},
          ),
        ),
      ),
    );

    await controller.loadHeadlines();
    await tester.pump();

    expect(find.text('Yeniden dene'), findsNothing);
    expect(find.textContaining('USCIS, çalışma izni uzatma'), findsWidgets);
  });

  testWidgets('forum trend isteği düşünce şerit sessizce kaybolmuyor', (
    tester,
  ) async {
    final controller = ForumController(repository: _BrokenForumRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumTrendingSection(
            controller: controller,
            onOpenForum: (_) {},
            onOpenTopic: (_) {},
          ),
        ),
      ),
    );

    await controller.loadTrending();
    await tester.pump();

    expect(find.text('Forumda trend tartışmalar'), findsOneWidget);
    expect(find.text('Trend tartışmalar yüklenemedi.'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
  });
}
