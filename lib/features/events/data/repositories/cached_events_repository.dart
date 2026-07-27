import '../../../../core/cache/cache_store.dart';
import '../../../../core/pagination/cached_cursor_data_source.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_event.dart';
import '../../domain/repositories/events_repository.dart';
import '../cache/events_page_codec.dart';

class CachedEventsRepository implements EventsRepository {
  CachedEventsRepository({required EventsRepository remote, required CacheStore cacheStore}) : _remote = remote, _cached = CachedCursorDataSource(remote: remote, cacheStore: cacheStore, codec: EventsPageCodec(), namespace: 'events.upcoming');
  final EventsRepository _remote;
  final CachedCursorDataSource<CommunityEvent> _cached;
  @override Future<CursorPage<CommunityEvent>> fetchPage({String? cursor, int limit = 20}) => _cached.fetchPage(cursor: cursor, limit: limit);
  @override Future<List<CommunityEvent>> getUpcomingEvents() => _remote.getUpcomingEvents();
  @override Future<CommunityEvent> updateRsvp({required String eventId, required EventRsvpStatus status}) => _remote.updateRsvp(eventId: eventId, status: status);
}
