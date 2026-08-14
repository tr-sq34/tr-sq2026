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
class ApiCommunityRepository
    implements
        CommunityRepository,
        FeedRepository,
        PostInteractionRepository,
        CommunityPostCommands,
        PollRepository,
        StoryRepository {
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
  Future<CommunityPost> setLike(String postId, bool isLiked) async {
    await _client.put<void>(
      '/community/posts/$postId/reactions/like',
      data: {'enabled': isLiked, 'idempotencyKey': _key()},
    );
    return _post(postId);
  }

  @override
  Future<CommunityPost> setSaved(String postId, bool isSaved) async {
    await _client.put<void>(
      '/community/posts/$postId/reactions/save',
      data: {'enabled': isSaved, 'idempotencyKey': _key()},
    );
    return _post(postId);
  }

  @override
  Future<CommunityPost> registerShare(String postId) async {
    await _client.post<void>(
      '/community/posts/$postId/shares',
      data: {'idempotencyKey': _key()},
    );
    return _post(postId);
  }

  /// Yüklenmiş medyanın kimliği sunucunun verdiği UUID; besteci elindeki yerel
  /// öğeye kendi kimliğini veriyor ve o kimlik sunucuda hiçbir şeye karşılık
  /// gelmiyor. Ayırt eden tek şey biçim.
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _isUploadedMedia(PostMedia media) => _uuid.hasMatch(media.id);

  Future<CommunityPost> _post(String postId) async => (await fetchFeed(
    mode: FeedMode.forYou,
    limit: 50,
  )).items.firstWhere((item) => item.id == postId);
  String _key() {
    final r = Random.secure();
    String s(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${s(8)}-${s(4)}-4${s(3)}-8${s(3)}-${s(12)}';
  }

  @override
  Future<CommunityPost> createPost(CreatePostDraft draft) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/community/posts',
      data: {
        'body': draft.normalizedMessage,
        'visibility': draft.visibility == PostVisibility.public
            ? 'public'
            : 'friends_only',
        // Boş alanlar hiç gönderilmiyor: sunucudaki şema bunları "optional"
        // sayıyor, ama `null` optional demek değil — konumsuz bir paylaşım
        // `locationLabel: null` yüzünden 400 alıyordu.
        if (draft.location?.displayName case final label?)
          'locationLabel': label,
        if (draft.marketplaceListingId case final listingId?)
          'marketplaceListingId': listingId,
        // Fotoğraflar kimlikleriyle gidiyor, adresleriyle değil: adres her
        // yanıtta yeniden imzalanan süreli bir izin, kalıcı bir alan değil.
        // Yalnızca yükleme servisinden dönmüş kimlikler gönderiliyor; besteci
        // yükleme tamamlanmadan da bir öğe taşıyabiliyor ve onun yerel kimliği
        // sunucuda hiçbir şeye karşılık gelmez.
        if (draft.media.where(_isUploadedMedia).isNotEmpty)
          'mediaIds': [
            for (final item in draft.media)
              if (_isUploadedMedia(item)) item.id,
          ],
        // Anketin sorusu ayrı gitmiyor; sunucuda da ayrı bir alan yok, gövde
        // metninin kendisi soru. Seçenekler sırasıyla kaydediliyor.
        if (draft.poll case final poll?)
          'poll': {
            'question': poll.question,
            'selectionMode': poll.selectionMode.name,
            'options': [
              for (final option in poll.options) option.label,
            ],
            if (poll.endsAt case final endsAt?)
              'closesAt': endsAt.toUtc().toIso8601String(),
          },
        'idempotencyKey': _key(),
      },
    );
    final id = ((response.data?['data'] as Map?)?['id'] as String?)!;
    return _post(id);
  }

  /// Oy 204 dönüyor, gövde yok: güncel dağılımı akıştan tekrar okuyup
  /// döndürüyoruz — sayacı burada tahmin etmek yanlış sonucu göstermek olurdu.
  @override
  Future<CommunityPoll> vote({
    required String postId,
    required String pollId,
    required Set<String> optionIds,
  }) async {
    await _client.post<void>(
      '/community/posts/$postId/poll/votes',
      data: {'optionIds': optionIds.toList(growable: false)},
    );
    final poll = (await _post(postId)).poll;
    if (poll == null) throw StateError('Anket bulunamadı.');
    return poll;
  }

  @override
  Future<void> deletePost(String postId) =>
      _client.delete<void>('/community/posts/$postId');

  @override
  Future<CursorPage<StoryItem>> fetchStories({
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityStories,
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiResponse<List<StoryItem>>.fromJson(response.data!, (
      raw,
    ) {
      return (raw as List<dynamic>)
          .map((value) => _storyFromJson(value as Map<String, dynamic>))
          .toList();
    });
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<StoryItem> createStory(CreateStoryDraft draft) async {
    if (draft.validationError case final error?) {
      throw ArgumentError(error);
    }
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityStories,
      data: {
        'mediaId': draft.media.id,
        'visibility': draft.visibility == StoryVisibility.public
            ? 'public'
            : 'network',
        'ttlHours': draft.ttl.inHours,
        'excludedUserIds': draft.excludedUserIds,
      },
    );
    final id = ((response.data?['data'] as Map?)?['id'] as String?);
    if (id == null) throw StateError('Story kimliği alınamadı.');
    return _story(id);
  }

  @override
  Future<StoryItem> markViewed(String storyId) async {
    await _client.post<void>('/community/stories/$storyId/views');
    return _story(storyId);
  }

  @override
  Future<StoryItem> setLiked(String storyId, bool isLiked) async {
    await _client.put<void>(
      '/community/stories/$storyId/likes',
      data: {'enabled': isLiked, 'idempotencyKey': _key()},
    );
    return _story(storyId);
  }

  Future<StoryItem> _story(String id) async =>
      (await fetchStories(limit: 50)).items.firstWhere((item) => item.id == id);

  @override
  Future<List<StoryAudienceContact>> fetchAudienceContacts() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityStoryAudienceContacts,
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((raw) {
          final json = raw as Map<String, dynamic>;
          return StoryAudienceContact(
            id: json['id'] as String,
            displayName: json['displayName'] as String,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> updateAudienceExclusions({
    required String storyId,
    required List<String> excludedUserIds,
  }) => _client.put<void>(
    '/community/stories/$storyId/audience/exclusions',
    data: {'excludedUserIds': excludedUserIds},
  );

  @override
  Future<List<StoryHighlight>> fetchMyHighlights() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityMyStoryHighlights,
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((raw) => _highlightFromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<StoryHighlight> createHighlight({
    required String title,
    required StoryVisibility visibility,
    required List<String> storyIds,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/community/story-highlights',
      data: {
        'title': title,
        'visibility': visibility == StoryVisibility.public
            ? 'public'
            : 'network',
        'storyIds': storyIds,
      },
    );
    final id = ((response.data?['data'] as Map?)?['id'] as String?);
    if (id == null) throw StateError('Öne çıkan Story kaydedilemedi.');
    return (await fetchMyHighlights()).firstWhere((item) => item.id == id);
  }

  StoryItem _storyFromJson(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>;
    return StoryItem(
      id: json['id'] as String,
      authorId: json['authorId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 3650)),
      visibility: json['visibility'] == 'public'
          ? StoryVisibility.public
          : StoryVisibility.network,
      media: PostMedia(
        id: media['id'] as String,
        type: media['type'] == 'video'
            ? PostMediaType.video
            : PostMediaType.image,
        url: media['url'] as String,
        thumbnailUrl: media['thumbnailUrl'] as String?,
      ),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      isViewed: json['isViewed'] as bool? ?? false,
    );
  }

  StoryHighlight _highlightFromJson(Map<String, dynamic> json) =>
      StoryHighlight(
        id: json['id'] as String,
        title: json['title'] as String,
        visibility: json['visibility'] == 'public'
            ? StoryVisibility.public
            : StoryVisibility.network,
        createdAt: DateTime.parse(json['createdAt'] as String),
        items: (json['items'] as List<dynamic>)
            .map((raw) {
              final item = raw as Map<String, dynamic>;
              final media = item['media'] as Map<String, dynamic>;
              return StoryItem(
                id: item['storyId'] as String,
                authorId: '',
                authorName: '',
                createdAt: DateTime.now(),
                expiresAt: DateTime.now().add(const Duration(days: 3650)),
                visibility: json['visibility'] == 'public'
                    ? StoryVisibility.public
                    : StoryVisibility.network,
                media: PostMedia(
                  id: media['id'] as String,
                  type: media['type'] == 'video'
                      ? PostMediaType.video
                      : PostMediaType.image,
                  url: media['url'] as String,
                  thumbnailUrl: media['thumbnailUrl'] as String?,
                ),
              );
            })
            .toList(growable: false),
      );

  @override
  Future<void> sendReply({required String storyId, required String message}) {
    throw UnsupportedError(
      'Story yanıtları güvenli mesajlaşma açıldığında etkinleşecek.',
    );
  }
}
