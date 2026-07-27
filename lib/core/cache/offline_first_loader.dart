import 'cache_codec.dart';
import 'cache_store.dart';

class OfflineFirstLoader<T> {
  OfflineFirstLoader({required CacheStore cacheStore, required CacheCodec<T> codec})
      : _cacheStore = cacheStore,
        _codec = codec;

  final CacheStore _cacheStore;
  final CacheCodec<T> _codec;

  Future<T?> readCached(String key) async {
    final raw = await _cacheStore.read(key);
    if (raw == null) return null;
    try {
      return _codec.decode(raw);
    } catch (_) {
      await _cacheStore.remove(key);
      return null;
    }
  }

  Future<void> cache(String key, T value) => _cacheStore.write(key, _codec.encode(value));
}
