import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_event.dart';
import '../../domain/repositories/events_repository.dart';
import '../dtos/community_event_dto.dart';

class ApiEventsRepository implements EventsRepository {
  ApiEventsRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  @override
  Future<CursorPage<CommunityEvent>> fetchPage({String? cursor, int limit = 20}) async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.eventsUpcoming, queryParameters: {'cursor': cursor, 'limit': limit});
    final envelope = ApiResponse<List<CommunityEvent>>.fromJson(response.data!, (raw) => (raw as List).map((item) => CommunityEventDto.fromJson(item as Map<String, dynamic>).toDomain()).toList());
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<CommunityEvent>> getUpcomingEvents() async => (await fetchPage()).items;

  @override
  Future<CommunityEvent> updateRsvp({required String eventId, required EventRsvpStatus status}) {
    // Endpoint contract is intentionally isolated here; UI/controller remain
    // unchanged when the live RSVP endpoint is connected.
    throw UnimplementedError('RSVP endpoint henüz yapılandırılmadı.');
  }
}
