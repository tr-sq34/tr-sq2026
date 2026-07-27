abstract interface class CacheCodec<T> {
  String encode(T value);
  T decode(String value);
}
