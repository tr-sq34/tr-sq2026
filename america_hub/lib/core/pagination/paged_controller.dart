import 'package:flutter/foundation.dart';

import 'cursor_data_source.dart';

enum PagedLoadState { initial, loading, loaded, refreshing, loadingMore, failure }

class PagedController<T> extends ChangeNotifier {
  PagedController({required CursorDataSource<T> dataSource, this.pageSize = 20}) : _dataSource = dataSource;

  final CursorDataSource<T> _dataSource;
  final int pageSize;
  final List<T> _items = [];

  PagedLoadState _state = PagedLoadState.initial;
  String? _nextCursor;
  String? _errorMessage;

  /// Uçuşta olan isteğin kuşağı.
  ///
  /// Akışta sekme değiştiren üye, cevabı yolda olan bir isteği geride
  /// bırakıyor. O cevap geldiğinde yazılacak liste artık başka bir sekmenin
  /// listesi: "Takip ettiklerin" sekmesinde bir an "Senin İçin" paylaşımları
  /// beliriyordu. Kuşak değişmişse cevap sessizce düşüyor.
  int _generation = 0;

  List<T> get items => List.unmodifiable(_items);
  PagedLoadState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get hasNextPage => _nextCursor != null && _nextCursor!.isNotEmpty;
  bool get isInitialLoading => _state == PagedLoadState.loading && _items.isEmpty;

  /// Listenin kaldığı yer. Listeyle birlikte alınıp birlikte geri konması
  /// gerekiyor: biri olmadan öteki, yanlış listenin devamını getirir.
  @protected
  String? get nextCursor => _nextCursor;

  /// For optimistic feature interactions such as likes and saved listings.
  void replaceItems(Iterable<T> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  /// Daha önce okunmuş bir listeyi imleciyle birlikte geri koyar.
  ///
  /// Sekmeler arasında gidip gelen üyeye her seferinde boş ekran göstermemek
  /// için: liste elde varken yeniden istemek, olanı saklamak demek.
  @protected
  void restoreItems(Iterable<T> items, {String? cursor}) {
    invalidate();
    _items
      ..clear()
      ..addAll(items);
    _nextCursor = cursor;
    _errorMessage = null;
    _state = _items.isEmpty ? PagedLoadState.initial : PagedLoadState.loaded;
    notifyListeners();
  }

  /// Uçuştaki isteğin cevabını sahipsiz bırakır.
  ///
  /// Durumu da sıfırlıyor, yoksa yarıda bırakılan istek "yükleniyor" olarak
  /// kaldığı sürece bir sonraki istek kapıdan giremiyordu - hızlı sekme
  /// değiştiren üyenin son sekmesi hiç yüklenmiyordu, sebebi buydu.
  @protected
  void invalidate() {
    _generation++;
    if (_state == PagedLoadState.loading ||
        _state == PagedLoadState.refreshing ||
        _state == PagedLoadState.loadingMore) {
      _state = PagedLoadState.initial;
    }
  }

  Future<void> loadInitial() async {
    if (_state == PagedLoadState.loading) return;
    final generation = _generation;
    _state = PagedLoadState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(limit: pageSize);
      if (generation != _generation) return;
      _items
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      if (generation != _generation) return;
      _state = PagedLoadState.failure;
      _errorMessage = 'İçerik yüklenemedi. Lütfen tekrar deneyin.';
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_state == PagedLoadState.refreshing) return;
    final generation = _generation;
    _state = PagedLoadState.refreshing;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(limit: pageSize);
      if (generation != _generation) return;
      _items
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      if (generation != _generation) return;
      _state = PagedLoadState.failure;
      _errorMessage = 'İçerik yenilenemedi. Lütfen tekrar deneyin.';
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    // İlk sayfa hâlâ yoldayken devamını istemek, iki cevabın birbirinin üstüne
    // yazması demek. Boş bir listenin sonuna varmak kolay olduğu için akışta
    // sekme değişir değişmez tetikleniyordu.
    if (!hasNextPage ||
        _state == PagedLoadState.loadingMore ||
        _state == PagedLoadState.loading ||
        _state == PagedLoadState.refreshing) {
      return;
    }
    final generation = _generation;
    _state = PagedLoadState.loadingMore;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(cursor: _nextCursor, limit: pageSize);
      if (generation != _generation) return;
      _items.addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      if (generation != _generation) return;
      _state = PagedLoadState.loaded;
      _errorMessage = 'Daha fazla içerik yüklenemedi.';
    }
    notifyListeners();
  }
}
