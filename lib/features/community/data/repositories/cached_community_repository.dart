import '../../../../core/cache/cache_store.dart';
import '../../../../core/pagination/cached_cursor_data_source.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';
import '../cache/community_page_codec.dart';

class CachedCommunityRepository implements CommunityRepository {
  CachedCommunityRepository({required CommunityRepository remote, required CacheStore cacheStore})
      : _remote = remote,
        _cacheStore = cacheStore,
        _cached = CachedCursorDataSource(remote: remote, cacheStore: cacheStore, codec: CommunityPageCodec(), namespace: 'community.feed');

  final CommunityRepository _remote;
  final CacheStore _cacheStore;
  final CachedCursorDataSource<CommunityPost> _cached;

  @override
  Future<CursorPage<CommunityPost>> fetchPage({String? cursor, int limit = 20}) => _cached.fetchPage(cursor: cursor, limit: limit);

  @override
  Future<List<CommunityPost>> getFeed() => _remote.getFeed();

  /// Yeni bir post veya silme işleminden sonra sonraki ilk yüklemenin
  /// güncel uzak veriyi istemesini sağlar. Cursor sayfaları yalnızca ilk
  /// sayfa yenilenince kullanılabilir olduğundan bu kadarı yeterlidir.
  Future<void> invalidateFirstPage({int limit = 2}) => _cacheStore.remove('community.feed:first:$limit');
}
