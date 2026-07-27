import 'dart:convert';
import '../../../../core/cache/cache_codec.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_event.dart';

class EventsPageCodec implements CacheCodec<CursorPage<CommunityEvent>> {
  @override
  CursorPage<CommunityEvent> decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return CursorPage(items: (data['items'] as List).map((item) { final map = item as Map<String, dynamic>; return CommunityEvent(id: map['id'], title: map['title'], category: map['category'], startsAt: DateTime.parse(map['startsAt']), endsAt: map['endsAt'] == null ? null : DateTime.parse(map['endsAt']), location: map['location'], city: map['city'], attendeeCount: map['attendeeCount'], priceLabel: map['priceLabel'], imageUrl: map['imageUrl'], description: map['description'] as String? ?? '', rsvpStatus: EventRsvpStatus.values.byName(map['rsvpStatus'] as String? ?? EventRsvpStatus.none.name)); }).toList(), nextCursor: data['nextCursor']);
  }
  @override
  String encode(CursorPage<CommunityEvent> value) => jsonEncode({'nextCursor': value.nextCursor, 'items': value.items.map((e) => {'id': e.id, 'title': e.title, 'category': e.category, 'startsAt': e.startsAt.toIso8601String(), 'endsAt': e.endsAt?.toIso8601String(), 'location': e.location, 'city': e.city, 'attendeeCount': e.attendeeCount, 'priceLabel': e.priceLabel, 'imageUrl': e.imageUrl, 'description': e.description, 'rsvpStatus': e.rsvpStatus.name}).toList()});
}
