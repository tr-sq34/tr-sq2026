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

  List<T> get items => List.unmodifiable(_items);
  PagedLoadState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get hasNextPage => _nextCursor != null && _nextCursor!.isNotEmpty;
  bool get isInitialLoading => _state == PagedLoadState.loading && _items.isEmpty;

  /// For optimistic feature interactions such as likes and saved listings.
  void replaceItems(Iterable<T> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  Future<void> loadInitial() async {
    if (_state == PagedLoadState.loading) return;
    _state = PagedLoadState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(limit: pageSize);
      _items
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      _state = PagedLoadState.failure;
      _errorMessage = 'İçerik yüklenemedi. Lütfen tekrar deneyin.';
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_state == PagedLoadState.refreshing) return;
    _state = PagedLoadState.refreshing;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(limit: pageSize);
      _items
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      _state = PagedLoadState.failure;
      _errorMessage = 'İçerik yenilenemedi. Lütfen tekrar deneyin.';
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasNextPage || _state == PagedLoadState.loadingMore) return;
    _state = PagedLoadState.loadingMore;
    notifyListeners();
    try {
      final page = await _dataSource.fetchPage(cursor: _nextCursor, limit: pageSize);
      _items.addAll(page.items);
      _nextCursor = page.nextCursor;
      _state = PagedLoadState.loaded;
    } catch (_) {
      _state = PagedLoadState.loaded;
      _errorMessage = 'Daha fazla içerik yüklenemedi.';
    }
    notifyListeners();
  }
}
