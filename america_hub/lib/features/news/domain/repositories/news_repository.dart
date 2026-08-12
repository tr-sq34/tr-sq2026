import '../../../../core/pagination/cursor_page.dart';
import '../entities/news_article.dart';

abstract interface class NewsRepository {
  Future<CursorPage<NewsArticle>> fetchNews({
    String? cursor,
    int limit = 20,
    NewsCategory? category,
  });

  /// Ana sayfanın manşet şeridi. Aynı depo, aynı haberler; farkı editörün
  /// verdiği sıra.
  Future<List<NewsArticle>> fetchHeadlines({int limit = 5});

  Future<NewsArticle> getArticle(String id);

  /// [reaction] null ise tepki geri alınır. Aynı ikona ikinci kez dokunmak oy
  /// tekrarı değil, oyu geri çekmektir.
  ///
  /// Dönen sayaçlar sunucunun saydığı sayılardır; istemci kendi tahminini
  /// tutmaz, çünkü iki cihazdan gelen tepkilerde tahmin tutmaz.
  Future<NewsReactionTally> react(String articleId, NewsReaction? reaction);
}

class NewsReactionTally {
  const NewsReactionTally({
    required this.likeCount,
    required this.dislikeCount,
    this.viewerReaction,
  });

  final int likeCount;
  final int dislikeCount;
  final NewsReaction? viewerReaction;

  factory NewsReactionTally.fromJson(Map<String, dynamic> json) =>
      NewsReactionTally(
        likeCount: json['likeCount'] as int? ?? 0,
        dislikeCount: json['dislikeCount'] as int? ?? 0,
        viewerReaction: NewsReaction.fromCode(json['viewerReaction'] as String?),
      );
}
