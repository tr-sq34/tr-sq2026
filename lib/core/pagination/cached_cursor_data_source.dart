import '../cache/cache_codec.dart';
import '../cache/cache_store.dart';
import 'cursor_data_source.dart';
import 'cursor_page.dart';

/// Reads the network first and falls back to the last successful page offline.
class CachedCursorDataSource<T> implements CursorDataSource<T> {
  CachedCursorDataSource({
    required CursorDataSource<T> remote,
    required CacheStore cacheStore,
    required CacheCodec<CursorPage<T>> codec,
    required String namespace,
  })  : _remote = remote,
        _cacheStore = cacheStore,
        _codec = codec,
        _namespace = namespace;

  final CursorDataSource<T> _remote;
  final CacheStore _cacheStore;
  final CacheCodec<CursorPage<T>> _codec;
  final String _namespace;

  @override
  Future<CursorPage<T>> fetchPage({String? cursor, int limit = 20}) async {
    final key = '$_namespace:${cursor ?? 'first'}:$limit';
    try {
      final page = await _remote.fetchPage(cursor: cursor, limit: limit);
      await _cacheStore.write(key, _codec.encode(page));
      return page;
    } catch (error) {
      final cached = await _cacheStore.read(key);
      if (cached == null) rethrow;
      return _codec.decode(cached);
    }
  }
}
