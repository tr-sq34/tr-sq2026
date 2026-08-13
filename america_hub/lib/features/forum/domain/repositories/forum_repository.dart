import '../../../../core/pagination/cursor_page.dart';
import '../entities/forum.dart';

/// Forumun tek sözleşmesi. Kategoriler bir liste hâlinde geliyor (sayıları
/// ondan az ve hepsi bir ekrana sığıyor), konular ve yanıtlar imleçli sayfayla:
/// bir yıllık arşivi tek istekte çekmenin anlamı yok.
abstract interface class ForumRepository {
  Future<List<ForumCategory>> fetchCategories();

  /// [categoryId] null ise bütün kategorilerden gelen konular tek listede.
  Future<CursorPage<ForumTopic>> fetchTopics({
    String? categoryId,
    String? cursor,
    int limit = 20,
    ForumTopicSort sort = ForumTopicSort.latestActivity,
  });

  /// Ana sayfadaki "Forumda trend tartışmalar" şeridi. Ayrı bir uç, çünkü
  /// oradaki sıra son hareket değil, konuşulma yoğunluğu.
  Future<List<ForumTopic>> fetchTrendingTopics({int limit = 5});

  /// Konuyu okumak aynı zamanda okunma sayacını artırır; sayının nerede
  /// artacağına sunucu karar verir, istemci kendi tahminini göstermez.
  Future<ForumTopic> fetchTopic(String topicId);

  Future<CursorPage<ForumReply>> fetchReplies(
    String topicId, {
    String? cursor,
    int limit = 30,
  });

  Future<ForumTopic> createTopic(CreateTopicDraft draft);

  Future<ForumReply> reply({required String topicId, required String body});

  Future<ForumTopic> setTopicLiked(String topicId, bool isLiked);

  Future<ForumReply> setReplyLiked(String replyId, bool isLiked);
}
