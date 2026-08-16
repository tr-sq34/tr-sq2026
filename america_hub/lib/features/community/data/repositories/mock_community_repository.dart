import '../../domain/entities/community_post.dart';
import '../../domain/entities/create_post_draft.dart';
import '../../domain/repositories/community_repository.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../../auth/domain/entities/app_user.dart';

class MockCommunityRepository
    implements
        CommunityRepository,
        CommunityPostCommands,
        CommunityPostArchive,
        FeedRepository,
        PostInteractionRepository,
        PollRepository,
        StoryRepository {
  /// Kim paylaşıyorsa paylaşım onun adına yazılsın diye. Sunucu tarafında yazarı
  /// zaten jeton belirliyor; burada bir kişi adı sabitlemek, üyenin kendi
  /// paylaşımını başkasının imzasıyla görmesi demekti — "Ahmet Yılmaz" tam
  /// olarak buydu. Testler ve önizlemeler bunu hiç vermeden de kurabilsin diye
  /// isteğe bağlı.
  MockCommunityRepository({
    AppUser? Function()? viewer,
    Future<String?> Function()? viewerRegion,
  }) : _viewer = viewer,
       _viewerRegion = viewerRegion;

  final AppUser? Function()? _viewer;

  /// "Yakınındakiler" sekmesi sunucuda üyenin seçtiği eyalete bakıyor; demo
  /// modun da aynı soruyu sorması gerekiyor, yoksa sekme her şeyi gösterip
  /// gerçekte olmayan bir davranışı öğretir.
  final Future<String?> Function()? _viewerRegion;

  static const _fallbackOwnerId = 'local-user';

  /// Profil ızgarası paylaşımları sahibine göre süzüyor: giriş yapılmamışken de
  /// iki taraf aynı kimliği görsün diye tek bir yerden okunuyor.
  String get viewerId => _viewer?.call()?.id ?? _fallbackOwnerId;

  final List<CommunityPost> _posts = [
    // Panelden akışa çıkarılmış bir haber. Demo modda da duruyor çünkü kartın
    // farkı gözle görülür: imzası Haber Bülteni, profili açılmıyor ve
    // dokunulduğunda haberin kendisine gidiyor. Bağlandığı kimlik demo haber
    // deposundaki gerçek bir haber - dokunuş boşa gitmiyor.
    CommunityPost(
      id: 'post-news-uscis',
      ownerId: 'news-desk',
      authorName: 'Haber Bülteni',
      location: 'Amerika geneli',
      timeLabel: '42 dk önce',
      message:
          'Otomatik uzatma süresi belirli kategorilerde 540 güne çıkarıldı. '
          'Başvurusu beklemede olan üyeler için kritik olan tarihleri derledik.',
      likes: 61,
      comments: 14,
      visibility: PostVisibility.public,
      commentsPolicy: CommentsPolicy.everyone,
      newsReference: const NewsPostReference(
        articleId: 'news-uscis',
        title:
            'USCIS, çalışma izni uzatma sürelerini ve başvuru kriterlerini güncelledi',
        category: 'gocmenlik',
      ),
    ),
    CommunityPost(
      id: 'post-1',
      ownerId: 'demo-elif',
      authorName: 'Elif Demir',
      location: 'New York, NY',
      timeLabel: '18 dk önce',
      message:
          'Bu hafta sonu Brooklyn’de güzel bir Türk kahvaltısı için buluşmak isteyen var mı? ☕️',
      likes: 24,
      comments: 8,
    ),
    CommunityPost(
      id: 'post-2',
      ownerId: 'demo-mert',
      authorName: 'Mert Kaya',
      location: 'Austin, TX',
      timeLabel: '2 sa önce',
      message:
          'Austin’deki yeni Türk marketini denedim. Özellikle taze simitleri harikaydı!',
      likes: 39,
      comments: 12,
      isLiked: true,
    ),
    CommunityPost(
      id: 'post-3',
      ownerId: 'demo-zeynep',
      authorName: 'Zeynep Arslan',
      location: 'Chicago, IL',
      timeLabel: '3 sa önce',
      message:
          'Haftaya çocuklar için Türkçe kitap takası yapıyoruz. Katılmak isteyenler yazabilir.',
      likes: 17,
      comments: 6,
    ),
    CommunityPost(
      id: 'post-4',
      ownerId: 'demo-can',
      authorName: 'Can Yılmaz',
      location: 'Seattle, WA',
      timeLabel: 'Dün',
      message: 'Seattle’daki Türk film gösterimi için bilet alan var mı?',
      likes: 11,
      comments: 4,
    ),
  ];
  /// Story rayı boş bir listeyle açıldığında ne ray ne de görüntüleyici
  /// gezilebiliyordu; demo modda sistemin çalıştığını göstermenin tek yolu
  /// birkaç hazır Story. Yalnızca bu mock dosyasında duruyorlar — gerçek
  /// `StoryController` hiçbir zaman örnek içeriğe düşmez.
  final List<StoryItem> _stories = [
    _demoStory(
      id: 'story-1',
      authorId: 'user-elif',
      authorName: 'Elif Demir',
      imageUrl:
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800',
      ageMinutes: 42,
      likeCount: 9,
      viewCount: 31,
    ),
    _demoStory(
      id: 'story-2',
      authorId: 'user-mert',
      authorName: 'Mert Kaya',
      imageUrl:
          'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      ageMinutes: 180,
      likeCount: 4,
      viewCount: 18,
    ),
    _demoStory(
      id: 'story-3',
      authorId: 'user-zeynep',
      authorName: 'Zeynep Arslan',
      imageUrl:
          'https://images.unsplash.com/photo-1521017432531-fbd92d768814?w=800',
      ageMinutes: 400,
      likeCount: 12,
      viewCount: 54,
    ),
  ];

  /// Story'ler 24 saat sonra düşer, dolayısıyla tarihleri sabit olamaz:
  /// uygulamanın açıldığı ana göre kurulurlar.
  static StoryItem _demoStory({
    required String id,
    required String authorId,
    required String authorName,
    required String imageUrl,
    required int ageMinutes,
    required int likeCount,
    required int viewCount,
  }) {
    final createdAt = DateTime.now().subtract(Duration(minutes: ageMinutes));
    return StoryItem(
      id: id,
      authorId: authorId,
      authorName: authorName,
      media: PostMedia(id: '$id-media', type: PostMediaType.image, url: imageUrl),
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(hours: 24)),
      visibility: StoryVisibility.network,
      likeCount: likeCount,
      viewCount: viewCount,
    );
  }

  @override
  Future<CursorPage<CommunityPost>> fetchPage({
    String? cursor,
    int limit = 20,
  }) async {
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final visiblePosts = _posts
        .where((post) => !post.isDeleted)
        .toList(growable: false);
    final safeEnd = (start + limit).clamp(0, visiblePosts.length).toInt();
    return CursorPage(
      items: visiblePosts.sublist(start, safeEnd),
      nextCursor: safeEnd < visiblePosts.length ? '$safeEnd' : null,
    );
  }

  @override
  Future<List<CommunityPost>> getFeed() async =>
      _posts.where((post) => !post.isDeleted).toList(growable: false);

  @override
  Future<CommunityPost> fetchPost(String postId) async {
    final post = _posts.firstWhere(
      (item) => item.id == postId && !item.isDeleted,
      orElse: () => throw StateError('POST_NOT_FOUND'),
    );
    return post;
  }

  @override
  Future<CursorPage<CommunityPost>> fetchFeed({
    required FeedMode mode,
    String? cursor,
    int limit = 20,
  }) async {
    if (mode == FeedMode.forYou) return fetchPage(cursor: cursor, limit: limit);
    final visible = _posts.where((post) => !post.isDeleted);
    // Takip kayıtları demo modda hiç yok; burada bir liste uydurmak yerine
    // sekme boş kalıyor — sunucuda da takip etmeyen biri boş görür.
    if (mode == FeedMode.following) return _pageOf(const [], cursor, limit);
    final region = (await _viewerRegion?.call())?.trim();
    if (region == null || region.isEmpty) return _pageOf(const [], cursor, limit);
    final suffix = ', ${region.toLowerCase()}';
    return _pageOf(
      visible
          .where((post) => post.location.toLowerCase().endsWith(suffix))
          .toList(growable: false),
      cursor,
      limit,
    );
  }

  CursorPage<CommunityPost> _pageOf(
    List<CommunityPost> posts,
    String? cursor,
    int limit,
  ) {
    final start = (int.tryParse(cursor ?? '0') ?? 0).clamp(0, posts.length);
    final end = (start + limit).clamp(0, posts.length).toInt();
    return CursorPage(
      items: posts.sublist(start, end),
      nextCursor: end < posts.length ? '$end' : null,
    );
  }

  @override
  Future<CommunityPost> setLike(String postId, bool isLiked) async =>
      _updatePost(
        postId,
        (post) => post.copyWith(
          isLiked: isLiked,
          likes:
              (post.likes +
                      (isLiked == post.isLiked
                          ? 0
                          : isLiked
                          ? 1
                          : -1))
                  .clamp(0, 1 << 31),
        ),
      );

  @override
  Future<CommunityPost> setSaved(String postId, bool isSaved) async =>
      _updatePost(
        postId,
        (post) => post.copyWith(
          isSaved: isSaved,
          saves:
              (post.saves +
                      (isSaved == post.isSaved
                          ? 0
                          : isSaved
                          ? 1
                          : -1))
                  .clamp(0, 1 << 31),
        ),
      );

  @override
  Future<CommunityPost> registerShare(String postId) async =>
      _updatePost(postId, (post) => post.copyWith(shares: post.shares + 1));

  @override
  Future<CommunityPoll> vote({
    required String postId,
    required String pollId,
    required Set<String> optionIds,
  }) async {
    final post = _posts.firstWhere((item) => item.id == postId);
    final poll = post.poll;
    if (poll == null || poll.id != pollId || poll.isClosed)
      throw StateError('Anket oylamaya açık değil.');
    if (poll.selectionMode == PollSelectionMode.single && optionIds.length != 1)
      throw ArgumentError('Bu ankette tek seçenek seçilebilir.');
    if (!optionIds.every((id) => poll.options.any((option) => option.id == id)))
      throw ArgumentError('Geçersiz anket seçeneği.');
    final updated = CommunityPoll(
      id: poll.id,
      question: poll.question,
      selectionMode: poll.selectionMode,
      endsAt: poll.endsAt,
      selectedOptionIds: optionIds,
      options: [
        for (final option in poll.options)
          PollOption(
            id: option.id,
            label: option.label,
            votes: option.votes + (optionIds.contains(option.id) ? 1 : 0),
          ),
      ],
    );
    _updatePost(postId, (item) => item.copyWith(poll: updated));
    return updated;
  }

  @override
  Future<CursorPage<StoryItem>> fetchStories({
    String? cursor,
    int limit = 30,
  }) async {
    final visible = _stories
        .where((item) => !item.isExpired)
        .toList(growable: false);
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + limit).clamp(0, visible.length).toInt();
    return CursorPage(
      items: visible.sublist(start, end),
      nextCursor: end < visible.length ? '$end' : null,
    );
  }

  @override
  Future<StoryItem> createStory(CreateStoryDraft draft) async {
    if (draft.validationError case final error?)
      throw ArgumentError.value(draft, 'draft', error);
    final story = StoryItem(
      id: 'story-${DateTime.now().microsecondsSinceEpoch}',
      authorId: viewerId,
      authorName: _viewer?.call()?.fullName ?? 'Sen',
      media: draft.media,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(draft.ttl),
      visibility: draft.visibility,
    );
    _stories.insert(0, story);
    return story;
  }

  @override
  Future<StoryItem> markViewed(String storyId) async => _updateStory(
    storyId,
    (story) => story.copyWith(
      isViewed: true,
      viewCount: story.isViewed ? story.viewCount : story.viewCount + 1,
    ),
  );
  @override
  Future<StoryItem> setLiked(String storyId, bool isLiked) async =>
      _updateStory(
        storyId,
        (story) => story.copyWith(
          isLiked: isLiked,
          likeCount:
              story.likeCount +
              (isLiked == story.isLiked
                  ? 0
                  : isLiked
                  ? 1
                  : -1),
        ),
      );

  @override
  Future<List<StoryAudienceContact>> fetchAudienceContacts() async => const [];

  @override
  Future<void> updateAudienceExclusions({
    required String storyId,
    required List<String> excludedUserIds,
  }) async {}

  @override
  Future<List<StoryHighlight>> fetchMyHighlights() async => const [];

  @override
  Future<StoryHighlight> createHighlight({
    required String title,
    required StoryVisibility visibility,
    required List<String> storyIds,
  }) {
    throw UnsupportedError('Mock Story öne çıkanları kullanılmıyor.');
  }

  @override
  Future<void> sendReply({
    required String storyId,
    required String message,
  }) async {
    if (message.trim().isEmpty || message.length > 1000)
      throw ArgumentError('Geçerli bir story yanıtı yazın.');
  }

  CommunityPost _updatePost(
    String id,
    CommunityPost Function(CommunityPost post) update,
  ) {
    final index = _posts.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Paylaşım bulunamadı.');
    return _posts[index] = update(_posts[index]);
  }

  StoryItem _updateStory(
    String id,
    StoryItem Function(StoryItem story) update,
  ) {
    final index = _stories.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Story bulunamadı.');
    return _stories[index] = update(_stories[index]);
  }

  @override
  Future<List<CommunityPost>> getPostsByOwner(String ownerId) async => _posts
      .where((post) => post.ownerId == ownerId && !post.isDeleted)
      .toList(growable: false);

  @override
  Future<CommunityPost> createPost(CreatePostDraft draft) async {
    final error = draft.validationError;
    if (error != null) throw ArgumentError.value(draft, 'draft', error);

    final post = CommunityPost(
      id: 'post-${DateTime.now().microsecondsSinceEpoch}',
      ownerId: viewerId,
      authorName: draft.purpose == CommunityPostPurpose.anonymousAdvice
          ? 'Anonim üye'
          : (_viewer?.call()?.fullName ?? 'Sen'),
      location: draft.location?.displayName ?? 'New York, NY',
      timeLabel: 'Şimdi',
      message: draft.normalizedMessage,
      likes: 0,
      comments: 0,
      visibility: draft.visibility,
      commentsPolicy: draft.commentsPolicy,
      media: draft.media,
      taggedUsers: draft.taggedUsers,
      postLocation: draft.location,
      purpose: draft.purpose,
      travelerMatch: draft.travelerMatch,
      badge: _badgeFor(draft.purpose),
      poll: draft.poll,
    );
    _posts.insert(0, post);
    return post;
  }

  CommunityBadge? _badgeFor(CommunityPostPurpose purpose) => switch (purpose) {
    CommunityPostPurpose.imeceHelp => const CommunityBadge(label: 'İmece'),
    CommunityPostPurpose.travelerMatch => const CommunityBadge(
      label: 'Yolculuk',
    ),
    CommunityPostPurpose.anonymousAdvice => const CommunityBadge(
      label: 'Anonim',
    ),
    CommunityPostPurpose.standard => null,
  };

  @override
  Future<void> deletePost(String postId) async {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) throw StateError('Paylaşım bulunamadı.');
    _posts[index] = _posts[index].copyWith(
      status: PostStatus.deleted,
      deletedAt: DateTime.now(),
    );
  }
}
