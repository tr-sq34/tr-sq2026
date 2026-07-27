import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/community_post.dart';
import '../domain/entities/create_post_draft.dart';
import '../domain/repositories/community_repository.dart';

class CommunityFeedController extends PagedController<CommunityPost> {
  CommunityFeedController({required CommunityRepository repository, required CommunityPostCommands commands, Future<void> Function()? onMutationCommitted})
      : _commands = commands,
        _onMutationCommitted = onMutationCommitted,
        super(dataSource: repository, pageSize: 2);

  final CommunityPostCommands _commands;
  final Future<void> Function()? _onMutationCommitted;

  Future<void> load() => loadInitial();

  void toggleLike(String postId) {
    replaceItems([
      for (final post in items)
        if (post.id == postId)
          post.copyWith(isLiked: !post.isLiked, likes: post.isLiked ? post.likes - 1 : post.likes + 1)
        else
          post,
    ]);
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
