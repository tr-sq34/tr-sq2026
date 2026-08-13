import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/forum.dart';
import '../../domain/repositories/forum_repository.dart';

class ApiForumRepository implements ForumRepository {
  ApiForumRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<ForumCategory>> fetchCategories() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityForumCategories,
    );
    return (response.data!['data'] as List<dynamic>)
        .map((item) => ForumCategory.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<CursorPage<ForumTopic>> fetchTopics({
    String? categoryId,
    String? cursor,
    int limit = 20,
    ForumTopicSort sort = ForumTopicSort.latestActivity,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityForumTopics,
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
        'sort': sort.name,
        'categoryId': ?categoryId,
      },
    );
    final envelope = ApiResponse<List<ForumTopic>>.fromJson(
      response.data!,
      _topics,
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<ForumTopic>> fetchTrendingTopics({int limit = 5}) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityForumTrending,
      queryParameters: {'limit': limit},
    );
    return _topics(response.data!['data']);
  }

  @override
  Future<ForumTopic> fetchTopic(String topicId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityForumTopic(topicId),
    );
    return ForumTopic.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<CursorPage<ForumReply>> fetchReplies(
    String topicId, {
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityForumReplies(topicId),
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiResponse<List<ForumReply>>.fromJson(
      response.data!,
      _replies,
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<ForumTopic> createTopic(CreateTopicDraft draft) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityForumTopics,
      data: {
        'categoryId': draft.categoryId,
        'title': draft.normalizedTitle,
        'body': draft.normalizedBody,
      },
    );
    return ForumTopic.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<ForumReply> reply({
    required String topicId,
    required String body,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityForumReplies(topicId),
      data: {'body': body.trim()},
    );
    return ForumReply.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<ForumTopic> setTopicLiked(String topicId, bool isLiked) async {
    final response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.communityForumTopicLike(topicId),
      data: {'value': isLiked},
    );
    return ForumTopic.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<ForumReply> setReplyLiked(String replyId, bool isLiked) async {
    final response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.communityForumReplyLike(replyId),
      data: {'value': isLiked},
    );
    return ForumReply.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  List<ForumTopic> _topics(Object? raw) => (raw as List<dynamic>)
      .map((item) => ForumTopic.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);

  List<ForumReply> _replies(Object? raw) => (raw as List<dynamic>)
      .map((item) => ForumReply.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
