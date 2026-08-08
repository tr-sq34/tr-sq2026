import '../entities/community_event.dart';
import '../../../../core/pagination/cursor_data_source.dart';

abstract interface class EventsRepository implements CursorDataSource<CommunityEvent> {
  Future<List<CommunityEvent>> getUpcomingEvents();
  Future<CommunityEvent> updateRsvp({
    required String eventId,
    required EventRsvpStatus status,
  });
}
