import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/news_article.dart';
import '../../domain/repositories/news_repository.dart';

class ApiNewsRepository implements NewsRepository {
  ApiNewsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<CursorPage<NewsArticle>> fetchNews({
    String? cursor,
    int limit = 20,
    NewsCategory? category,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityNews,
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        if (category != null) 'category': category.code,
      },
    );
    final envelope = ApiResponse<List<NewsArticle>>.fromJson(
      response.data!,
      _articles,
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<NewsArticle>> fetchHeadlines({int limit = 5}) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityNewsHeadlines,
      queryParameters: {'limit': limit},
    );
    return _articles(response.data!['data']);
  }

  @override
  Future<NewsArticle> getArticle(String id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityNewsArticle(id),
    );
    return NewsArticle.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<NewsReactionTally> react(
    String articleId,
    NewsReaction? reaction,
  ) async {
    final response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.communityNewsReactions(articleId),
      data: {'value': reaction?.name},
    );
    return NewsReactionTally.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }

  List<NewsArticle> _articles(Object? raw) => (raw as List<dynamic>)
      .map((item) => NewsArticle.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
