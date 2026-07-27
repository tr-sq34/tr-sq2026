import 'dart:math';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/create_post_draft.dart';
import '../../domain/repositories/community_repository.dart';
import '../../domain/entities/feed_extensions.dart';
import '../dtos/community_post_dto.dart';

/// Activate this repository only after the backend response contract is confirmed.
class ApiCommunityRepository implements CommunityRepository, FeedRepository, PostInteractionRepository, CommunityPostCommands {
  ApiCommunityRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  @override
  Future<CursorPage<CommunityPost>> fetchPage({
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityFeed,
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiResponse<List<CommunityPost>>.fromJson(
      response.data!,
      (raw) => (raw as List<dynamic>)
          .map(
            (item) => CommunityPostDto.fromJson(
              item as Map<String, dynamic>,
            ).toDomain(),
          )
          .toList(),
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<CommunityPost>> getFeed() async => (await fetchPage()).items;

  @override
  Future<CursorPage<CommunityPost>> fetchFeed({
    required FeedMode mode,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityFeed,
      queryParameters: {'mode': mode.name, 'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiResponse<List<CommunityPost>>.fromJson(
      response.data!,
      (raw) => (raw as List<dynamic>)
          .map(
            (item) => CommunityPostDto.fromJson(
              item as Map<String, dynamic>,
            ).toDomain(),
          )
          .toList(),
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<CommunityPost> setLike(String postId, bool isLiked) async { await _client.put<void>('/community/posts/$postId/reactions/like',data:{'enabled':isLiked,'idempotencyKey':_key()}); return _post(postId); }
  @override
  Future<CommunityPost> setSaved(String postId, bool isSaved) async { await _client.put<void>('/community/posts/$postId/reactions/save',data:{'enabled':isSaved,'idempotencyKey':_key()}); return _post(postId); }
  @override
  Future<CommunityPost> registerShare(String postId) async { await _client.post<void>('/community/posts/$postId/shares',data:{'idempotencyKey':_key()}); return _post(postId); }
  Future<CommunityPost> _post(String postId) async => (await fetchFeed(mode: FeedMode.forYou,limit:50)).items.firstWhere((item)=>item.id==postId);
  String _key(){final r=Random.secure();String s(int n)=>List.generate(n,(_)=>r.nextInt(16).toRadixString(16)).join();return '${s(8)}-${s(4)}-4${s(3)}-8${s(3)}-${s(12)}';}
  @override
  Future<CommunityPost> createPost(CreatePostDraft draft) async { final response=await _client.post<Map<String,dynamic>>('/community/posts',data:{'body':draft.normalizedMessage,'visibility':draft.visibility==PostVisibility.public?'public':'friends_only','locationLabel':draft.location?.displayName,'marketplaceListingId':draft.marketplaceListingId,'idempotencyKey':_key()}); final id=((response.data?['data'] as Map?)?['id'] as String?)!; return _post(id); }
  @override
  Future<void> deletePost(String postId) => _client.delete<void>('/community/posts/$postId');
}
