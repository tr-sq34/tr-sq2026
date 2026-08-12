import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/news_article.dart';
import '../domain/repositories/news_repository.dart';

/// Haber Merkezi listesi, ana sayfanın manşet şeridi ve açılan haberin kendisi
/// — üçü de tek denetleyicide, çünkü üçü de aynı kaydın görünümü. Bir haberi
/// beğendiğinde sayacın listede de güncellenmesi bundan.
class NewsController extends ChangeNotifier {
  NewsController({required NewsRepository repository})
    : _repository = repository;

  final NewsRepository _repository;

  AsyncState<List<NewsArticle>> _articles = const AsyncLoading();
  AsyncState<List<NewsArticle>> get articles => _articles;

  AsyncState<List<NewsArticle>> _headlines = const AsyncLoading();
  AsyncState<List<NewsArticle>> get headlines => _headlines;

  NewsCategory? _category;
  NewsCategory? get category => _category;

  /// Açık olan haberin tam hâli. Liste yalnızca özeti taşır, gövde detay
  /// ucundan gelir.
  final Map<String, NewsArticle> _opened = {};

  Future<void> load({NewsCategory? category}) async {
    _category = category;
    _articles = const AsyncLoading();
    notifyListeners();
    try {
      final page = await _repository.fetchNews(category: category);
      _articles = AsyncData(page.items);
    } catch (_) {
      _articles = const AsyncFailure('Haberler yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> loadHeadlines() async {
    _headlines = const AsyncLoading();
    notifyListeners();
    try {
      _headlines = AsyncData(await _repository.fetchHeadlines());
    } catch (_) {
      _headlines = const AsyncFailure('Manşetler yüklenemedi.');
    }
    notifyListeners();
  }

  NewsArticle? opened(String id) => _opened[id];

  Future<NewsArticle> openArticle(String id) async {
    final article = await _repository.getArticle(id);
    _opened[id] = article;
    _replace(article);
    notifyListeners();
    return article;
  }

  /// Açık olan tepkiye ikinci kez dokunmak onu geri alır; bu yüzden gönderilen
  /// değer, dokunulan ikon değil, dokunuştan sonraki durumdur.
  Future<void> react(String articleId, NewsReaction reaction) async {
    final current = _articleById(articleId);
    final next = current?.viewerReaction == reaction ? null : reaction;
    final tally = await _repository.react(articleId, next);
    final updated = (current ?? _opened[articleId])?.copyWith(
      likeCount: tally.likeCount,
      dislikeCount: tally.dislikeCount,
      viewerReaction: tally.viewerReaction,
      clearViewerReaction: tally.viewerReaction == null,
    );
    if (updated != null) {
      if (_opened.containsKey(articleId)) _opened[articleId] = updated;
      _replace(updated);
    }
    notifyListeners();
  }

  /// Yorum eklendikten sonra sayacın ekranda da artması için.
  void registerComment(String articleId) {
    final current = _articleById(articleId) ?? _opened[articleId];
    if (current == null) return;
    final updated = current.copyWith(commentCount: current.commentCount + 1);
    if (_opened.containsKey(articleId)) _opened[articleId] = updated;
    _replace(updated);
    notifyListeners();
  }

  NewsArticle? _articleById(String id) {
    for (final list in [_articles, _headlines]) {
      if (list case AsyncData<List<NewsArticle>>(:final value)) {
        for (final article in value) {
          if (article.id == id) return article;
        }
      }
    }
    return _opened[id];
  }

  /// Aynı haber listede de manşette de olabilir; ikisini birden güncellemezsek
  /// kullanıcı geri döndüğünde eski sayacı görür.
  void _replace(NewsArticle article) {
    _articles = _replaceIn(_articles, article);
    _headlines = _replaceIn(_headlines, article);
  }

  static AsyncState<List<NewsArticle>> _replaceIn(
    AsyncState<List<NewsArticle>> state,
    NewsArticle article,
  ) {
    if (state case AsyncData<List<NewsArticle>>(:final value)) {
      if (!value.any((item) => item.id == article.id)) return state;
      return AsyncData([
        for (final item in value)
          if (item.id == article.id)
            // Gövde yalnızca detayda dolu; listedeki kaydın gövdesiz kalması
            // doğru, ama sayaçlar ve tepki her iki yerde de aynı olmalı.
            item.copyWith(
              likeCount: article.likeCount,
              dislikeCount: article.dislikeCount,
              commentCount: article.commentCount,
              viewerReaction: article.viewerReaction,
              clearViewerReaction: article.viewerReaction == null,
            )
          else
            item,
      ]);
    }
    return state;
  }
}
