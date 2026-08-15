/// Forumun tamamı üç kayıttan ibaret: bir kategori, içindeki konular ve konunun
/// altındaki yanıtlar. Akıştan ayrı durmasının sebebi ömrü: akış bugünün
/// gündemi, forum ise bir yıl sonra da aranıp bulunacak bir soru-cevap arşivi.
library;

import '../../../../core/formatting/relative_time.dart';

class ForumCategory {
  const ForumCategory({
    required this.id,
    required this.slug,
    required this.title,
    required this.emoji,
    this.description = '',
    this.topicCount = 0,
    this.replyCount = 0,
    this.lastActivityAt,
  });

  final String id;
  final String slug;
  final String title;

  /// Kategori simgesi. Panelden yazılıyor; uygulamada ikon eşleştirme tablosu
  /// tutmak, yeni kategori açmayı sürüm çıkarmaya bağlardı.
  final String emoji;
  final String description;
  final int topicCount;
  final int replyCount;
  final DateTime? lastActivityAt;

  factory ForumCategory.fromJson(Map<String, dynamic> json) => ForumCategory(
    id: json['id'] as String,
    slug: json['slug'] as String,
    title: json['title'] as String,
    emoji: json['emoji'] as String? ?? '💬',
    description: json['description'] as String? ?? '',
    topicCount: json['topicCount'] as int? ?? 0,
    replyCount: json['replyCount'] as int? ?? 0,
    lastActivityAt: DateTime.tryParse(
      json['lastActivityAt'] as String? ?? '',
    )?.toLocal(),
  );
}

class ForumTopic {
  const ForumTopic({
    required this.id,
    required this.categoryId,
    required this.categoryTitle,
    required this.title,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.replyCount = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.isLiked = false,
    this.isPinned = false,
    this.isLocked = false,
    this.lastReplyAt,
    this.lastReplyAuthorName,
  });

  final String id;
  final String categoryId;
  final String categoryTitle;
  final String title;
  final String body;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final int replyCount;
  final int viewCount;
  final int likeCount;
  final bool isLiked;

  /// Moderasyon kararları: sabitlenen konu listenin başında durur, kilitlenen
  /// konuya yeni yanıt yazılamaz ama okunmaya devam eder.
  final bool isPinned;
  final bool isLocked;
  final DateTime? lastReplyAt;
  final String? lastReplyAuthorName;

  /// Listede en üste çıkacak konu, en son yazılan yanıtı olan konudur; hiç
  /// yanıt almamışsa açıldığı an sayılır.
  DateTime get lastActivityAt => lastReplyAt ?? createdAt;

  /// "Sıcak tartışma" rozeti bir editör kararı değil, ölçülen bir şey: son
  /// günün içinde konuşulmaya devam eden ve yanıt almış konular.
  bool get isHot =>
      replyCount >= 5 &&
      DateTime.now().difference(lastActivityAt) < const Duration(days: 1);

  ForumTopic copyWith({
    int? replyCount,
    int? viewCount,
    int? likeCount,
    bool? isLiked,
    bool? isPinned,
    bool? isLocked,
    DateTime? lastReplyAt,
    String? lastReplyAuthorName,
  }) => ForumTopic(
    id: id,
    categoryId: categoryId,
    categoryTitle: categoryTitle,
    title: title,
    body: body,
    authorId: authorId,
    authorName: authorName,
    createdAt: createdAt,
    replyCount: replyCount ?? this.replyCount,
    viewCount: viewCount ?? this.viewCount,
    likeCount: likeCount ?? this.likeCount,
    isLiked: isLiked ?? this.isLiked,
    isPinned: isPinned ?? this.isPinned,
    isLocked: isLocked ?? this.isLocked,
    lastReplyAt: lastReplyAt ?? this.lastReplyAt,
    lastReplyAuthorName: lastReplyAuthorName ?? this.lastReplyAuthorName,
  );

  factory ForumTopic.fromJson(Map<String, dynamic> json) => ForumTopic(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String,
    categoryTitle: json['categoryTitle'] as String? ?? '',
    title: json['title'] as String,
    body: json['body'] as String? ?? '',
    authorId: json['authorId'] as String? ?? '',
    authorName: json['authorName'] as String? ?? 'Üye',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    replyCount: json['replyCount'] as int? ?? 0,
    viewCount: json['viewCount'] as int? ?? 0,
    likeCount: json['likeCount'] as int? ?? 0,
    isLiked: json['isLiked'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    isLocked: json['isLocked'] as bool? ?? false,
    lastReplyAt: DateTime.tryParse(
      json['lastReplyAt'] as String? ?? '',
    )?.toLocal(),
    lastReplyAuthorName: json['lastReplyAuthorName'] as String?,
  );
}

class ForumReply {
  const ForumReply({
    required this.id,
    required this.topicId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
    this.isAcceptedAnswer = false,
  });

  final String id;
  final String topicId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;

  /// Soruyu soran, işine yarayan yanıtı işaretleyebilir. Forumun akıştan farkı
  /// da burada: bir konunun bir cevabı olabiliyor.
  final bool isAcceptedAnswer;

  ForumReply copyWith({int? likeCount, bool? isLiked, bool? isAcceptedAnswer}) =>
      ForumReply(
        id: id,
        topicId: topicId,
        authorId: authorId,
        authorName: authorName,
        body: body,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        isLiked: isLiked ?? this.isLiked,
        isAcceptedAnswer: isAcceptedAnswer ?? this.isAcceptedAnswer,
      );

  factory ForumReply.fromJson(Map<String, dynamic> json) => ForumReply(
    id: json['id'] as String,
    topicId: json['topicId'] as String,
    authorId: json['authorId'] as String? ?? '',
    authorName: json['authorName'] as String? ?? 'Üye',
    body: json['body'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    likeCount: json['likeCount'] as int? ?? 0,
    isLiked: json['isLiked'] as bool? ?? false,
    isAcceptedAnswer: json['isAcceptedAnswer'] as bool? ?? false,
  );
}

/// "8 dk önce" — konu listesinde, detayda ve ana sayfadaki şeritte aynı biçim.
///
/// Biçimin kendisi artık [timeAgoVerbose] içinde: akış da aynı soruyu soruyor,
/// iki ayrı kopya zamanla iki ayrı cevap verirdi.
String forumTimeAgo(DateTime moment, {DateTime? now}) =>
    timeAgoVerbose(moment, now: now);

/// Yeni konu açarken taşınan geçici veri. Doğrulama burada duruyor ki ekran da
/// depo da aynı kuralı iki ayrı yerde yeniden yazmasın.
class CreateTopicDraft {
  const CreateTopicDraft({
    required this.categoryId,
    required this.title,
    required this.body,
  });

  final String categoryId;
  final String title;
  final String body;

  static const maxTitleLength = 160;
  static const maxBodyLength = 8000;

  String get normalizedTitle => title.trim();
  String get normalizedBody => body.trim();

  String? get validationError {
    if (categoryId.isEmpty) return 'Bir kategori seçin.';
    if (normalizedTitle.length < 8) {
      return 'Başlık en az 8 karakter olmalı; arayan biri bulabilsin.';
    }
    if (normalizedTitle.length > maxTitleLength) {
      return 'Başlık en fazla $maxTitleLength karakter olabilir.';
    }
    if (normalizedBody.length < 20) {
      return 'Sorunu biraz açar mısın? En az 20 karakter.';
    }
    if (normalizedBody.length > maxBodyLength) {
      return 'Konu metni en fazla $maxBodyLength karakter olabilir.';
    }
    return null;
  }
}

/// Konu listesinin sıralaması. Varsayılan "son hareket": forumda yeni açılmış
/// ama kimsenin okumadığı bir konu, hâlâ konuşulan bir konunun önüne geçmemeli.
enum ForumTopicSort { latestActivity, newest, mostReplies }
