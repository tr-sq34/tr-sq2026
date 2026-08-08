import 'package:flutter/foundation.dart';

import '../../../core/pagination/cursor_page.dart';
import '../domain/entities/feed_extensions.dart';
import '../domain/repositories/community_repository.dart';

/// Owns Story pagination separately from the feed. A Story rail never falls
/// back to sample users when the signed-in member has no visible Stories.
class StoryController extends ChangeNotifier {
  StoryController({required StoryRepository repository})
    : _repository = repository;

  final StoryRepository _repository;
  final List<StoryItem> _items = [];
  final List<StoryHighlight> _highlights = [];
  String? _nextCursor;
  bool _loading = false;
  String? _errorMessage;

  List<StoryItem> get items => List.unmodifiable(_items);
  List<StoryHighlight> get highlights => List.unmodifiable(_highlights);

  /// The rail has one tile per author, while the full-screen viewer retains
  /// each sequential Story from that author. This prevents a prolific member
  /// from crowding out the rest of the signed-in member's network.
  List<StoryItem> get railItems {
    final seenAuthors = <String>{};
    return List.unmodifiable(
      _items.where((item) => !item.isExpired && seenAuthors.add(item.authorId)),
    );
  }

  bool get isLoading => _loading;
  bool get hasMore => _nextCursor != null;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.fetchStories();
      _replace(page);
    } catch (_) {
      _errorMessage = 'Story’ler şu anda yüklenemedi.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _nextCursor == null) return;
    _loading = true;
    notifyListeners();
    try {
      final page = await _repository.fetchStories(cursor: _nextCursor);
      _items.addAll(page.items);
      _nextCursor = page.nextCursor;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markViewed(String storyId) async {
    final index = _items.indexWhere((item) => item.id == storyId);
    if (index < 0 || _items[index].isViewed) return;
    final original = _items[index];
    _items[index] = original.copyWith(
      isViewed: true,
      viewCount: original.viewCount + 1,
    );
    notifyListeners();
    try {
      await _repository.markViewed(storyId);
    } catch (_) {
      _items[index] = original;
      notifyListeners();
    }
  }

  Future<void> setLiked(String storyId, bool isLiked) async {
    final index = _items.indexWhere((item) => item.id == storyId);
    if (index < 0) return;
    final original = _items[index];
    final count =
        original.likeCount +
        (isLiked == original.isLiked
            ? 0
            : isLiked
            ? 1
            : -1);
    _items[index] = original.copyWith(
      isLiked: isLiked,
      likeCount: count < 0 ? 0 : count,
    );
    notifyListeners();
    try {
      await _repository.setLiked(storyId, isLiked);
    } catch (_) {
      _items[index] = original;
      notifyListeners();
    }
  }

  Future<StoryItem> create(CreateStoryDraft draft) async {
    final story = await _repository.createStory(draft);
    _items.insert(0, story);
    notifyListeners();
    return story;
  }

  Future<List<StoryAudienceContact>> loadAudienceContacts() =>
      _repository.fetchAudienceContacts();

  Future<void> setAudienceExclusions({
    required String storyId,
    required List<String> excludedUserIds,
  }) => _repository.updateAudienceExclusions(
    storyId: storyId,
    excludedUserIds: excludedUserIds,
  );

  Future<void> loadHighlights() async {
    try {
      final results = await _repository.fetchMyHighlights();
      _highlights
        ..clear()
        ..addAll(results);
      notifyListeners();
    } catch (_) {
      // Highlights are a profile enhancement; keep the profile usable if this
      // optional request is temporarily unavailable.
    }
  }

  Future<void> createHighlight({
    required String title,
    required StoryVisibility visibility,
    required List<String> storyIds,
  }) async {
    final highlight = await _repository.createHighlight(
      title: title,
      visibility: visibility,
      storyIds: storyIds,
    );
    _highlights.insert(0, highlight);
    notifyListeners();
  }

  void _replace(CursorPage<StoryItem> page) {
    _items
      ..clear()
      ..addAll(page.items.where((item) => !item.isExpired));
    _nextCursor = page.nextCursor;
  }
}
