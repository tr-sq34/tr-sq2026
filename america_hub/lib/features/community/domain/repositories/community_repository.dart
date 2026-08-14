import '../entities/community_post.dart';
import '../entities/create_post_draft.dart';
import '../../../../core/pagination/cursor_data_source.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../entities/feed_extensions.dart';

abstract interface class CommunityRepository
    implements CursorDataSource<CommunityPost> {
  Future<List<CommunityPost>> getFeed();
}

/// Yazma işlemleri, sayfalı okuma sözleşmesinden bilinçli olarak ayrıdır.
/// Bu ayrım cache'li veya salt-okunur bir feed kaynağının yanlışlıkla mutasyon
/// yapmasını engeller.
abstract interface class CommunityPostCommands {
  Future<CommunityPost> createPost(CreatePostDraft draft);
  Future<void> deletePost(String postId);
}

/// Profildeki "Akışlar" sekmesi, feed'in bir kopyasını tutmaz; aynı post
/// kaynağını sahip kimliğiyle sorgular.
abstract interface class CommunityPostArchive {
  Future<List<CommunityPost>> getPostsByOwner(String ownerId);
}

abstract interface class CommunityCommentsRepository {
  Future<List<CommunityComment>> getComments(String postId);
  Future<CommunityComment> createComment({
    required String postId,
    required String message,
    String? parentId,
  });
  Future<void> deleteComment(String commentId);

  /// Kalp açık mı kapalı mı — kaç arttığı değil, ne olması gerektiği.
  ///
  /// İstek son durumu söylüyor, bu yüzden aynı isteğin ikinci kez gitmesi
  /// sayıyı ikiye katlamıyor; bağlantı koparsa uygulama tazelendiğinde
  /// sunucudaki cevap neyse o kalıyor.
  Future<void> setCommentLike({required String commentId, required bool liked});
}

abstract interface class FeedRepository {
  Future<CursorPage<CommunityPost>> fetchFeed({
    required FeedMode mode,
    String? cursor,
    int limit = 20,
  });
}

abstract interface class PostInteractionRepository {
  Future<CommunityPost> setLike(String postId, bool isLiked);
  Future<CommunityPost> setSaved(String postId, bool isSaved);
  Future<CommunityPost> registerShare(String postId);
}

abstract interface class PollRepository {
  Future<CommunityPoll> vote({
    required String postId,
    required String pollId,
    required Set<String> optionIds,
  });
}

abstract interface class StoryRepository {
  Future<CursorPage<StoryItem>> fetchStories({String? cursor, int limit = 30});
  Future<StoryItem> createStory(CreateStoryDraft draft);
  Future<StoryItem> markViewed(String storyId);
  Future<StoryItem> setLiked(String storyId, bool isLiked);
  Future<List<StoryAudienceContact>> fetchAudienceContacts();
  Future<void> updateAudienceExclusions({
    required String storyId,
    required List<String> excludedUserIds,
  });
  Future<List<StoryHighlight>> fetchMyHighlights();
  Future<StoryHighlight> createHighlight({
    required String title,
    required StoryVisibility visibility,
    required List<String> storyIds,
  });
  Future<void> sendReply({required String storyId, required String message});
}

abstract interface class LocationRepository {
  Future<ApproximateLocation?> currentApproximateLocation();
  Future<List<ApproximateLocation>> search(String query);
}
