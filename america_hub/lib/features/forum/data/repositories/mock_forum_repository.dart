import '../../../../core/pagination/cursor_page.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../domain/entities/forum.dart';
import '../../domain/repositories/forum_repository.dart';

/// Sunucu açılana kadar forumu ayakta tutan demo içerik.
///
/// Kategoriler paneldeki listenin aynısı; konular ve yanıtlar ise forumun neye
/// benzediğini gösterecek kadar. Yazan kişi hiçbir zaman uydurulmuyor: yeni
/// açılan konu da yazılan yanıt da giriş yapmış üyenin adıyla kaydediliyor.
class MockForumRepository implements ForumRepository {
  MockForumRepository({AppUser? Function()? viewer}) : _viewer = viewer;

  final AppUser? Function()? _viewer;

  String get _viewerId => _viewer?.call()?.id ?? 'local-user';
  String get _viewerName => _viewer?.call()?.fullName ?? 'Sen';

  late final List<ForumCategory> _categories = _seedCategories();
  late final List<ForumTopic> _topics = _seedTopics();
  late final List<ForumReply> _replies = _seedReplies();

  @override
  Future<List<ForumCategory>> fetchCategories() async => [
    for (final category in _categories)
      ForumCategory(
        id: category.id,
        slug: category.slug,
        title: category.title,
        emoji: category.emoji,
        description: category.description,
        // Sayaçlar kategorinin üstünde yazan sabitler değil, o an listede
        // duran konuların sayısı.
        topicCount: _topics.where((t) => t.categoryId == category.id).length,
        replyCount: _topics
            .where((t) => t.categoryId == category.id)
            .fold(0, (total, topic) => total + topic.replyCount),
        lastActivityAt: _topics
            .where((t) => t.categoryId == category.id)
            .map((t) => t.lastActivityAt)
            .fold<DateTime?>(
              null,
              (latest, value) =>
                  latest == null || value.isAfter(latest) ? value : latest,
            ),
      ),
  ];

  @override
  Future<CursorPage<ForumTopic>> fetchTopics({
    String? categoryId,
    String? cursor,
    int limit = 20,
    ForumTopicSort sort = ForumTopicSort.latestActivity,
  }) async {
    final filtered =
        _topics
            .where((topic) => categoryId == null || topic.categoryId == categoryId)
            .toList()
          ..sort((a, b) {
            // Sabitlenen konu her sıralamada en üstte: moderasyon kararı,
            // sıralama tercihinin üstünde durur.
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return switch (sort) {
              ForumTopicSort.latestActivity => b.lastActivityAt.compareTo(
                a.lastActivityAt,
              ),
              ForumTopicSort.newest => b.createdAt.compareTo(a.createdAt),
              ForumTopicSort.mostReplies => b.replyCount.compareTo(a.replyCount),
            };
          });
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + limit).clamp(0, filtered.length).toInt();
    return CursorPage(
      items: filtered.sublist(start, end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<List<ForumTopic>> fetchTrendingTopics({int limit = 5}) async {
    final ranked = _topics.toList()
      ..sort((a, b) {
        final byReplies = b.replyCount.compareTo(a.replyCount);
        return byReplies != 0
            ? byReplies
            : b.lastActivityAt.compareTo(a.lastActivityAt);
      });
    return ranked.take(limit).toList(growable: false);
  }

  @override
  Future<ForumTopic> fetchTopic(String topicId) async {
    final index = _indexOfTopic(topicId);
    // Okundu sayacı burada artıyor: gerçek serviste de sayan taraf sunucu.
    return _topics[index] = _topics[index].copyWith(
      viewCount: _topics[index].viewCount + 1,
    );
  }

  @override
  Future<CursorPage<ForumReply>> fetchReplies(
    String topicId, {
    String? cursor,
    int limit = 30,
  }) async {
    final all = _replies.where((reply) => reply.topicId == topicId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + limit).clamp(0, all.length).toInt();
    return CursorPage(
      items: all.sublist(start, end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  @override
  Future<ForumTopic> createTopic(CreateTopicDraft draft) async {
    if (draft.validationError case final error?) {
      throw ArgumentError.value(draft, 'draft', error);
    }
    final category = _categories.firstWhere(
      (item) => item.id == draft.categoryId,
      orElse: () => throw StateError('Kategori bulunamadı.'),
    );
    final topic = ForumTopic(
      id: 'topic-${DateTime.now().microsecondsSinceEpoch}',
      categoryId: category.id,
      categoryTitle: category.title,
      title: draft.normalizedTitle,
      body: draft.normalizedBody,
      authorId: _viewerId,
      authorName: _viewerName,
      createdAt: DateTime.now(),
    );
    _topics.insert(0, topic);
    return topic;
  }

  @override
  Future<ForumReply> reply({
    required String topicId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) throw ArgumentError('Yanıt boş olamaz.');
    final index = _indexOfTopic(topicId);
    if (_topics[index].isLocked) {
      throw StateError('Bu konu kapatıldı, yeni yanıt yazılamıyor.');
    }
    final reply = ForumReply(
      id: 'reply-${DateTime.now().microsecondsSinceEpoch}',
      topicId: topicId,
      authorId: _viewerId,
      authorName: _viewerName,
      body: trimmed,
      createdAt: DateTime.now(),
    );
    _replies.add(reply);
    _topics[index] = _topics[index].copyWith(
      replyCount: _topics[index].replyCount + 1,
      lastReplyAt: reply.createdAt,
      lastReplyAuthorName: reply.authorName,
    );
    return reply;
  }

  @override
  Future<ForumTopic> setTopicLiked(String topicId, bool isLiked) async {
    final index = _indexOfTopic(topicId);
    final topic = _topics[index];
    if (topic.isLiked == isLiked) return topic;
    return _topics[index] = topic.copyWith(
      isLiked: isLiked,
      likeCount: (topic.likeCount + (isLiked ? 1 : -1)).clamp(0, 1 << 31),
    );
  }

  @override
  Future<ForumReply> setReplyLiked(String replyId, bool isLiked) async {
    final index = _replies.indexWhere((reply) => reply.id == replyId);
    if (index < 0) throw StateError('Yanıt bulunamadı.');
    final reply = _replies[index];
    if (reply.isLiked == isLiked) return reply;
    return _replies[index] = reply.copyWith(
      isLiked: isLiked,
      likeCount: (reply.likeCount + (isLiked ? 1 : -1)).clamp(0, 1 << 31),
    );
  }

  int _indexOfTopic(String topicId) {
    final index = _topics.indexWhere((topic) => topic.id == topicId);
    if (index < 0) throw StateError('Konu bulunamadı.');
    return index;
  }

  static List<ForumCategory> _seedCategories() => const [
    ForumCategory(
      id: 'cat-vize',
      slug: 'vize-gocmenlik',
      title: 'Vize & Göçmenlik',
      emoji: '🎓',
      description: 'Vize türleri, yeşil kart, vatandaşlık ve randevular',
    ),
    ForumCategory(
      id: 'cat-emlak',
      slug: 'emlak-yasam',
      title: 'Emlak & Yaşam',
      emoji: '🏠',
      description: 'Kiralama, ev alma, mahalleler ve taşınma',
    ),
    ForumCategory(
      id: 'cat-is',
      slug: 'is-kurma-yatirim',
      title: 'İş Kurma & Yatırım',
      emoji: '💼',
      description: 'Şirket kurma, vergi, işletme devri ve yatırım',
    ),
    ForumCategory(
      id: 'cat-egitim',
      slug: 'egitim-okul',
      title: 'Eğitim & Okul',
      emoji: '📚',
      description: 'Okul kayıtları, üniversite ve çocuklar için Türkçe',
    ),
    ForumCategory(
      id: 'cat-gunluk',
      slug: 'gunluk-hayat',
      title: 'Günlük Hayat',
      emoji: '🛒',
      description: 'Ehliyet, sağlık, alışveriş ve şehirdeki pratik bilgiler',
    ),
  ];

  static List<ForumTopic> _seedTopics() {
    final now = DateTime.now();
    return [
      ForumTopic(
        id: 'topic-e2',
        categoryId: 'cat-is',
        categoryTitle: 'İş Kurma & Yatırım',
        title:
            'E-2 vizesiyle küçük işletme devralma süreci ve kendi tecrübelerim',
        body:
            'İki yıl önce E-2 ile geldik, Paterson\'da küçük bir market devraldık. '
            'Sürecin tamamını, avukat masraflarını ve devir sırasında dikkat '
            'ettiğimiz şeyleri yazayım dedim. Sorusu olan buraya yazsın.',
        authorId: 'demo-burak',
        authorName: 'Burak Kılıç',
        createdAt: now.subtract(const Duration(days: 9)),
        replyCount: 48,
        viewCount: 2412,
        likeCount: 36,
        lastReplyAt: now.subtract(const Duration(minutes: 8)),
        lastReplyAuthorName: 'Selin A.',
      ),
      ForumTopic(
        id: 'topic-h1b',
        categoryId: 'cat-vize',
        categoryTitle: 'Vize & Göçmenlik',
        title: 'H-1B kurası çıkmayanlar için bu yıl hangi seçenekler kaldı?',
        body:
            'Kurada çıkmadım, işveren desteklemeye devam ediyor. O-1, L-1 ve '
            'öğrenci statüsüne dönüş dışında düşünmediğim bir yol var mı?',
        authorId: 'demo-elif',
        authorName: 'Elif Demir',
        createdAt: now.subtract(const Duration(days: 3)),
        replyCount: 21,
        viewCount: 940,
        likeCount: 14,
        lastReplyAt: now.subtract(const Duration(hours: 2)),
        lastReplyAuthorName: 'Mert K.',
      ),
      ForumTopic(
        id: 'topic-kiralik',
        categoryId: 'cat-emlak',
        categoryTitle: 'Emlak & Yaşam',
        title: 'Kredi geçmişi olmadan kiralık ev tutmak: ne işe yaradı?',
        body:
            'Yeni geldik, SSN var ama kredi geçmişi yok. Ev sahipleri peşin '
            'birkaç kira istiyor. Bu durumu aşan oldu mu, nasıl?',
        authorId: 'demo-zeynep',
        authorName: 'Zeynep Arslan',
        createdAt: now.subtract(const Duration(days: 1)),
        replyCount: 12,
        viewCount: 480,
        likeCount: 9,
        lastReplyAt: now.subtract(const Duration(hours: 5)),
        lastReplyAuthorName: 'Can Y.',
      ),
      ForumTopic(
        id: 'topic-kurallar',
        categoryId: 'cat-gunluk',
        categoryTitle: 'Günlük Hayat',
        title: 'Forum kuralları: neyi nereye yazıyoruz?',
        body:
            'Konu açmadan önce arama yapın, başlığı arayan biri bulabilsin diye '
            'yazın, ilan paylaşımı Çarşı sekmesine ait. Kişisel bilgi '
            'paylaşmayın; hukuki ve göçmenlik konularında yazılanlar tecrübe '
            'aktarımıdır, avukat tavsiyesi değildir.',
        authorId: 'demo-moderator',
        authorName: 'TurkSquare Ekibi',
        createdAt: now.subtract(const Duration(days: 40)),
        replyCount: 0,
        viewCount: 3120,
        likeCount: 51,
        isPinned: true,
        isLocked: true,
      ),
      ForumTopic(
        id: 'topic-ehliyet',
        categoryId: 'cat-gunluk',
        categoryTitle: 'Günlük Hayat',
        title: 'NJ ehliyet sınavı: randevu, evraklar ve sınav günü',
        body:
            'Geçen hafta aldım, sırayla ne istediklerini yazıyorum. Randevuyu '
            'sabahın ilk saatine almak gerçekten fark ediyor.',
        authorId: 'demo-can',
        authorName: 'Can Yılmaz',
        createdAt: now.subtract(const Duration(days: 6)),
        replyCount: 7,
        viewCount: 620,
        likeCount: 11,
        lastReplyAt: now.subtract(const Duration(hours: 20)),
        lastReplyAuthorName: 'Zeynep A.',
      ),
    ];
  }

  static List<ForumReply> _seedReplies() {
    final now = DateTime.now();
    return [
      ForumReply(
        id: 'reply-e2-1',
        topicId: 'topic-e2',
        authorId: 'demo-mert',
        authorName: 'Mert Kaya',
        body:
            'Devir sırasında satıcının vergi borcu olup olmadığını mutlaka '
            'kontrol ettirin. Bizde escrow hesabı bu yüzden iki ay bekledi.',
        createdAt: now.subtract(const Duration(days: 8)),
        likeCount: 12,
        isAcceptedAnswer: true,
      ),
      ForumReply(
        id: 'reply-e2-2',
        topicId: 'topic-e2',
        authorId: 'demo-selin',
        authorName: 'Selin Aydın',
        body:
            'Avukat masrafı bizde 6-8 bin dolar aralığındaydı. Başvuru '
            'dosyasındaki iş planını ciddiye alın, en çok oradan soru geliyor.',
        createdAt: now.subtract(const Duration(minutes: 8)),
        likeCount: 4,
      ),
      ForumReply(
        id: 'reply-h1b-1',
        topicId: 'topic-h1b',
        authorId: 'demo-mert',
        authorName: 'Mert Kaya',
        body:
            'Kanada üzerinden L-1 yolunu deneyen tanıdıklarım oldu; şirketin '
            'orada bir yıl çalıştırması gerekiyor ama işliyor.',
        createdAt: now.subtract(const Duration(hours: 2)),
        likeCount: 6,
      ),
      ForumReply(
        id: 'reply-kiralik-1',
        topicId: 'topic-kiralik',
        authorId: 'demo-can',
        authorName: 'Can Yılmaz',
        body:
            'İşveren yazısı ve banka ekstresini birlikte götürünce iki ev '
            'sahibi de kabul etti. Bir de kefil isteyen çıkabiliyor.',
        createdAt: now.subtract(const Duration(hours: 5)),
        likeCount: 3,
      ),
      ForumReply(
        id: 'reply-ehliyet-1',
        topicId: 'topic-ehliyet',
        authorId: 'demo-zeynep',
        authorName: 'Zeynep Arslan',
        body:
            '6 Puan belgesi listesini önceden hazırlayın; eksik evrakla giden '
            'randevusunu yakıyor.',
        createdAt: now.subtract(const Duration(hours: 20)),
        likeCount: 5,
      ),
    ];
  }
}
