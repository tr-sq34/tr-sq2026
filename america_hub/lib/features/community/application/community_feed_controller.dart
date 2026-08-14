import '../../../core/pagination/cursor_data_source.dart';
import '../../../core/pagination/cursor_page.dart';
import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/community_post.dart';
import '../domain/entities/create_post_draft.dart';
import '../domain/entities/feed_extensions.dart';
import '../domain/repositories/community_repository.dart';

/// Sekmeyi sunucuya taşıyan kaynak.
///
/// "Senin İçin" hâlâ önbellekli depodan geliyor — açılışta görünen ilk sayfa o,
/// ve çevrimdışı açılan uygulamanın gösterebildiği tek şey de o. Diğer iki sekme
/// önbelleğe girmiyor: kimi takip ettiğin ve nerede olduğun, eski bir sayfanın
/// doğru cevap veremeyeceği sorular.
class _FeedModeSource implements CursorDataSource<CommunityPost> {
  _FeedModeSource({required this.cached, required this.feed});

  final CursorDataSource<CommunityPost> cached;
  final FeedRepository feed;
  FeedMode mode = FeedMode.forYou;

  @override
  Future<CursorPage<CommunityPost>> fetchPage({String? cursor, int limit = 20}) =>
      mode == FeedMode.forYou
          ? cached.fetchPage(cursor: cursor, limit: limit)
          : feed.fetchFeed(mode: mode, cursor: cursor, limit: limit);
}

class CommunityFeedController extends PagedController<CommunityPost> {
  factory CommunityFeedController({
    required CommunityRepository repository,
    required FeedRepository feed,
    required CommunityPostCommands commands,
    required PostInteractionRepository interactions,
    required PollRepository polls,
    Future<void> Function()? onMutationCommitted,
  }) => CommunityFeedController._(
    _FeedModeSource(cached: repository, feed: feed),
    commands: commands,
    interactions: interactions,
    polls: polls,
    onMutationCommitted: onMutationCommitted,
  );

  CommunityFeedController._(
    _FeedModeSource source, {
    required CommunityPostCommands commands,
    required PostInteractionRepository interactions,
    required PollRepository polls,
    Future<void> Function()? onMutationCommitted,
  })  : _source = source,
        _commands = commands,
        _interactions = interactions,
        _polls = polls,
        _onMutationCommitted = onMutationCommitted,
        super(dataSource: source, pageSize: 2);

  final _FeedModeSource _source;

  /// Bildirimden gelen paylaşım listede olmayabilir: akış ilk sayfayı gösterir,
  /// yorum ise iki hafta önceki bir paylaşıma gelmiş olabilir. Sunucuya tek tek
  /// soruluyor.
  Future<CommunityPost> fetchPost(String postId) =>
      _source.feed.fetchPost(postId);
  final CommunityPostCommands _commands;
  final PostInteractionRepository _interactions;
  final PollRepository _polls;
  final Future<void> Function()? _onMutationCommitted;

  FeedMode get mode => _source.mode;

  Future<void> load() => loadInitial();

  /// Sekme değişince liste sunucudan yeniden geliyor.
  ///
  /// Eskiden üç sekme aynı sayfayı istemcide süzüyordu: "Yakınındakiler"
  /// paylaşımın adresinde "New York" arıyordu — New York'ta olmayan herkes için
  /// boş, orada olanlar için rastgele — "Takip ettiklerin" ise kendi
  /// paylaşımlarını gizlemekten ibaretti. İkisi de sunucunun zaten bildiği
  /// sorunun yanlış cevabıydı.
  Future<void> setMode(FeedMode mode) async {
    if (_source.mode == mode) return;
    _source.mode = mode;
    // Önceki sekmenin gönderileri yeni sekmenin altında beklemesin: yanlış
    // listeyi bir an gostermek, boş bir liste göstermekten daha kafa karıştırıcı.
    replaceItems(const []);
    await loadInitial();
  }

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

  /// Ankete oy vermek. Sonuç sunucudan dönen sayaçlarla değişiyor: iyimser bir
  /// güncelleme yapıp yanılmaktansa, oy verildikten sonra gerçek dağılımı
  /// göstermek daha doğru — anketin tek işi zaten doğru sayıyı göstermek.
  Future<void> voteOnPoll({
    required String postId,
    required String pollId,
    required Set<String> optionIds,
  }) async {
    final updated = await _polls.vote(
      postId: postId,
      pollId: pollId,
      optionIds: optionIds,
    );
    replaceItems([
      for (final post in items)
        if (post.id == postId) post.copyWith(poll: updated) else post,
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
