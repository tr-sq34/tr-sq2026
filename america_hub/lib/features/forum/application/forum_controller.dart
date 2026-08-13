import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/forum.dart';
import '../domain/repositories/forum_repository.dart';

/// Kategori listesi, konu listesi, açık konu ve yanıtları — dördü tek
/// denetleyicide. Sebebi haberdekiyle aynı: bir konuya yanıt yazıldığında
/// sayacın geri dönülen listede de artmış olması gerekiyor.
class ForumController extends ChangeNotifier {
  ForumController({required ForumRepository repository})
    : _repository = repository;

  final ForumRepository _repository;

  AsyncState<List<ForumCategory>> _categories = const AsyncLoading();
  AsyncState<List<ForumCategory>> get categories => _categories;

  AsyncState<List<ForumTopic>> _topics = const AsyncLoading();
  AsyncState<List<ForumTopic>> get topics => _topics;

  AsyncState<List<ForumTopic>> _trending = const AsyncLoading();
  AsyncState<List<ForumTopic>> get trending => _trending;

  AsyncState<List<ForumReply>> _replies = const AsyncLoading();
  AsyncState<List<ForumReply>> get replies => _replies;

  /// null ise bütün kategoriler tek listede.
  String? _categoryId;
  String? get categoryId => _categoryId;

  ForumTopicSort _sort = ForumTopicSort.latestActivity;
  ForumTopicSort get sort => _sort;

  ForumTopic? _openTopic;
  ForumTopic? get openTopic => _openTopic;

  String? _topicsCursor;
  bool _loadingMore = false;
  bool get hasMoreTopics => _topicsCursor != null;

  bool _sending = false;
  bool get isSending => _sending;

  Future<void> load() async {
    await loadCategories();
    await loadTopics(categoryId: _categoryId);
  }

  /// Ana sayfadaki şerit yalnızca kategori adlarına ve trend konulara ihtiyaç
  /// duyuyor; konu listesinin tamamını çekmesi için bir sebep yok.
  Future<void> loadCategories() async {
    _categories = const AsyncLoading();
    notifyListeners();
    try {
      _categories = AsyncData(await _repository.fetchCategories());
    } catch (_) {
      _categories = const AsyncFailure('Forum kategorileri yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> loadTopics({String? categoryId, ForumTopicSort? sort}) async {
    _categoryId = categoryId;
    _sort = sort ?? _sort;
    _topics = const AsyncLoading();
    _topicsCursor = null;
    notifyListeners();
    try {
      final page = await _repository.fetchTopics(
        categoryId: _categoryId,
        sort: _sort,
      );
      _topics = AsyncData(page.items);
      _topicsCursor = page.nextCursor;
    } catch (_) {
      _topics = const AsyncFailure('Konular yüklenemedi.');
    }
    notifyListeners();
  }

  /// Liste sonuna gelindiğinde çağrılıyor; eldeki sayfa yenisiyle değil,
  /// devamıyla birleşiyor.
  Future<void> loadMoreTopics() async {
    final cursor = _topicsCursor;
    if (cursor == null || _loadingMore) return;
    if (_topics case AsyncData<List<ForumTopic>>(:final value)) {
      _loadingMore = true;
      try {
        final page = await _repository.fetchTopics(
          categoryId: _categoryId,
          cursor: cursor,
          sort: _sort,
        );
        _topics = AsyncData([...value, ...page.items]);
        _topicsCursor = page.nextCursor;
        notifyListeners();
      } catch (_) {
        // Sonraki sayfanın gelmemesi, ekrandaki listeyi hata ekranına
        // çevirmemeli: üye okuduğu yerde kalsın.
      } finally {
        _loadingMore = false;
      }
    }
  }

  Future<void> loadTrending({int limit = 3}) async {
    _trending = const AsyncLoading();
    notifyListeners();
    try {
      _trending = AsyncData(await _repository.fetchTrendingTopics(limit: limit));
    } catch (_) {
      _trending = const AsyncFailure('Trend tartışmalar yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> openTopicById(String topicId) async {
    _openTopic = _topicById(topicId);
    _replies = const AsyncLoading();
    notifyListeners();
    try {
      _openTopic = await _repository.fetchTopic(topicId);
      _replaceTopic(_openTopic!);
      _replies = AsyncData((await _repository.fetchReplies(topicId)).items);
    } catch (_) {
      _replies = const AsyncFailure('Yanıtlar yüklenemedi.');
    }
    notifyListeners();
  }

  void closeTopic() {
    _openTopic = null;
    _replies = const AsyncLoading();
  }

  /// Yeni konu açıldığında listeye eklemek yerine baştan yükleniyor: sıralama
  /// kuralını burada ikinci kez yazmak, iki yerin ayrışması demek.
  Future<ForumTopic> createTopic(CreateTopicDraft draft) async {
    _sending = true;
    notifyListeners();
    try {
      final topic = await _repository.createTopic(draft);
      await loadTopics(categoryId: _categoryId);
      _categories = AsyncData(await _repository.fetchCategories());
      return topic;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> reply(String topicId, String body) async {
    _sending = true;
    notifyListeners();
    try {
      final reply = await _repository.reply(topicId: topicId, body: body);
      if (_replies case AsyncData<List<ForumReply>>(:final value)) {
        _replies = AsyncData([...value, reply]);
      }
      final topic = _openTopic;
      if (topic != null && topic.id == topicId) {
        _openTopic = topic.copyWith(
          replyCount: topic.replyCount + 1,
          lastReplyAt: reply.createdAt,
          lastReplyAuthorName: reply.authorName,
        );
        _replaceTopic(_openTopic!);
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> toggleTopicLike(String topicId) async {
    final current = _topicById(topicId);
    if (current == null) return;
    final updated = await _repository.setTopicLiked(topicId, !current.isLiked);
    if (_openTopic?.id == topicId) _openTopic = updated;
    _replaceTopic(updated);
    notifyListeners();
  }

  Future<void> toggleReplyLike(String replyId) async {
    if (_replies case AsyncData<List<ForumReply>>(:final value)) {
      final current = value.where((reply) => reply.id == replyId).firstOrNull;
      if (current == null) return;
      final updated = await _repository.setReplyLiked(replyId, !current.isLiked);
      _replies = AsyncData([
        for (final reply in value) reply.id == replyId ? updated : reply,
      ]);
      notifyListeners();
    }
  }

  ForumTopic? _topicById(String id) {
    for (final state in [_topics, _trending]) {
      if (state case AsyncData<List<ForumTopic>>(:final value)) {
        final match = value.where((topic) => topic.id == id).firstOrNull;
        if (match != null) return match;
      }
    }
    return _openTopic?.id == id ? _openTopic : null;
  }

  /// Aynı konu hem listede hem trend şeridinde durabiliyor; ikisi birden
  /// güncellenmezse üye geri döndüğünde eski sayacı görür.
  void _replaceTopic(ForumTopic topic) {
    _topics = _replaceIn(_topics, topic);
    _trending = _replaceIn(_trending, topic);
  }

  static AsyncState<List<ForumTopic>> _replaceIn(
    AsyncState<List<ForumTopic>> state,
    ForumTopic topic,
  ) {
    if (state case AsyncData<List<ForumTopic>>(:final value)) {
      if (!value.any((item) => item.id == topic.id)) return state;
      return AsyncData([
        for (final item in value) item.id == topic.id ? topic : item,
      ]);
    }
    return state;
  }
}
