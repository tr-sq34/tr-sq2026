import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/community_post.dart';
import '../domain/entities/create_post_draft.dart';
import '../domain/repositories/community_repository.dart';

class CommunityFeedController extends PagedController<CommunityPost> {
  CommunityFeedController({
    required CommunityRepository repository,
    required CommunityPostCommands commands,
    required PostInteractionRepository interactions,
    Future<void> Function()? onMutationCommitted,
  })  : _commands = commands,
        _interactions = interactions,
        _onMutationCommitted = onMutationCommitted,
        super(dataSource: repository, pageSize: 2);

  final CommunityPostCommands _commands;
  final PostInteractionRepository _interactions;
  final Future<void> Function()? _onMutationCommitted;

  Future<void> load() => loadInitial();

  Future<void> toggleLike(String postId) async {
    CommunityPost? previous;
    for (final post in items) {
      if (post.id == postId) {
        previous = post;
        break;
      }
    }
    if (previous == null) return;
    final optimistic = previous.copyWith(
      isLiked: !previous.isLiked,
      likes: previous.isLiked ? previous.likes - 1 : previous.likes + 1,
    );
    replaceItems([
      for (final post in items) if (post.id == postId) optimistic else post,
    ]);
    try {
      final confirmed = await _interactions.setLike(postId, optimistic.isLiked);
      replaceItems([
        for (final post in items) if (post.id == postId) confirmed else post,
      ]);
      await _onMutationCommitted?.call();
    } catch (_) {
      replaceItems([
        for (final post in items) if (post.id == postId) previous else post,
      ]);
    }
  }

  Future<CommunityPost> createPost(CreatePostDraft draft) async {
    final post = await _commands.createPost(draft);
    replaceItems([post, ...items]);
    await _onMutationCommitted?.call();
    return post;
  }

  /// Başarılı silme sonrası post feed'den anında çıkar. Sunucu tarafında ise
  /// kayıt soft-delete olarak tutulur; profil ve feed tekrar yüklenince de dönmez.
  Future<void> deletePost(String postId) async {
    await _commands.deletePost(postId);
    replaceItems(items.where((post) => post.id != postId).toList(growable: false));
    await _onMutationCommitted?.call();
  }
}
