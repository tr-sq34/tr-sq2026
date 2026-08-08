import '../../domain/entities/community_event.dart';
import '../../domain/repositories/events_repository.dart';
import '../../../../core/pagination/cursor_page.dart';

class MockEventsRepository implements EventsRepository {
  late final List<CommunityEvent> _events = [
        CommunityEvent(id: 'event-1', title: 'Turkish Summer Picnic', category: 'Community', startsAt: DateTime(2026, 8, 2, 12), endsAt: DateTime(2026, 8, 2, 16), location: 'Central Park', city: 'New York, NY', attendeeCount: 86, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1506126613408-eca07ce68773?auto=format&fit=crop&w=900&q=80', description: 'Central Park\'ta piknik, müzik ve çocuklar için atölyelerle yaz buluşması.'),
        CommunityEvent(id: 'event-2', title: 'Anatolian Jazz Night', category: 'Music', startsAt: DateTime(2026, 8, 8, 19, 30), endsAt: DateTime(2026, 8, 8, 22), location: 'The Whistler', city: 'Chicago, IL', attendeeCount: 42, priceLabel: '\$18', imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=900&q=80', description: 'Anadolu ezgileri ve cazın bir araya geldiği samimi akşam.'),
        CommunityEvent(id: 'event-3', title: 'Turkish Coffee Workshop', category: 'Culture', startsAt: DateTime(2026, 8, 15, 11), endsAt: DateTime(2026, 8, 15, 13), location: 'Sonder Coffee', city: 'Austin, TX', attendeeCount: 24, priceLabel: '\$12', imageUrl: 'https://images.unsplash.com/photo-1544787219-7f47ccb76574?auto=format&fit=crop&w=900&q=80', description: 'Türk kahvesinin hikâyesi, demleme incelikleri ve birlikte tadım.'),
        CommunityEvent(id: 'event-4', title: 'Simit ve Sohbet', category: 'Community', startsAt: DateTime(2026, 8, 17, 10), endsAt: DateTime(2026, 8, 17, 12), location: 'Astoria Park', city: 'Queens, NY', attendeeCount: 31, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=900&q=80', description: 'Hafta sonuna simit, cay ve yeni tanisacak komsularla baslayalim.'),
        CommunityEvent(id: 'event-5', title: 'Bogaz Lezzetleri', category: 'Food', startsAt: DateTime(2026, 8, 21, 18, 30), endsAt: DateTime(2026, 8, 21, 21), location: 'Brooklyn Kitchen', city: 'Brooklyn, NY', attendeeCount: 18, priceLabel: '\$25', imageUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=900&q=80', description: 'Ege ve Anadolu mutfagindan kolay tarifler, tadim ve sohbet.'),
        CommunityEvent(id: 'event-6', title: 'Aile Piknigi', category: 'Community', startsAt: DateTime(2026, 8, 23, 13), endsAt: DateTime(2026, 8, 23, 17), location: 'Liberty State Park', city: 'Jersey City, NJ', attendeeCount: 57, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=900&q=80', description: 'Cocuk oyunlari, ortak masa ve tum aile icin acik hava bulusmasi.'),
        CommunityEvent(id: 'event-7', title: 'Turk Filmleri Gecesi', category: 'Culture', startsAt: DateTime(2026, 8, 29, 20), endsAt: DateTime(2026, 8, 29, 22, 30), location: 'Soho Cinema', city: 'Manhattan, NY', attendeeCount: 46, priceLabel: '\$10', imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=900&q=80', description: 'Bagimsiz Turk sinemasindan secili bir film ve gosteri sonrasi sohbet.'),
        CommunityEvent(id: 'event-8', title: 'Acik Hava Sinemasi', category: 'Cinema', startsAt: DateTime(2026, 9, 3, 20), endsAt: DateTime(2026, 9, 3, 23), location: 'Bryant Park', city: 'New York, NY', attendeeCount: 64, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=900&q=80', description: 'Parkta acik hava filmi ve gosteri oncesi piknik bulusmasi.'),
        CommunityEvent(id: 'event-9', title: 'Genc Sanatcilar Sergisi', category: 'Exhibition', startsAt: DateTime(2026, 9, 6, 14), endsAt: DateTime(2026, 9, 6, 18), location: 'Brooklyn Art Hall', city: 'Brooklyn, NY', attendeeCount: 22, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1561214115-8d4e0b8a0995?auto=format&fit=crop&w=900&q=80', description: 'Genc sanatcilarin resim, fotograf ve tasarim sergisi.'),
        CommunityEvent(id: 'event-10', title: 'Hudson Sonbahar Gezisi', category: 'Travel', startsAt: DateTime(2026, 9, 12, 9), endsAt: DateTime(2026, 9, 12, 17), location: 'Hudson Valley', city: 'New York, NY', attendeeCount: 38, priceLabel: '\$35', imageUrl: 'https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=900&q=80', description: 'Hudson vadisinde gunluk gezi, manzara ve kahvalti molasi.'),
        CommunityEvent(id: 'event-11', title: 'Ebru Atolyesi', category: 'Workshop', startsAt: DateTime(2026, 9, 19, 13), endsAt: DateTime(2026, 9, 19, 16), location: 'Turk Evi', city: 'New York, NY', attendeeCount: 16, priceLabel: '\$20', imageUrl: 'https://images.unsplash.com/photo-1544787219-7f47ccb76574?auto=format&fit=crop&w=900&q=80', description: 'Geleneksel ebru teknigini deneyimleyebilecegin uygulamali atölye.'),
        CommunityEvent(id: 'event-12', title: 'Renkli Sonbahar Festivali', category: 'Festival', startsAt: DateTime(2026, 9, 26, 12), endsAt: DateTime(2026, 9, 26, 20), location: 'Liberty Plaza', city: 'Jersey City, NJ', attendeeCount: 110, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=900&q=80', description: 'Canli muzik, lezzet stantlari ve aile etkinlikleriyle sonbahar festivali.'),
        CommunityEvent(id: 'event-13', title: 'Aile Oyun Gunu', category: 'Family', startsAt: DateTime(2026, 10, 4, 11), endsAt: DateTime(2026, 10, 4, 15), location: 'Riverside Hall', city: 'Paterson, NJ', attendeeCount: 51, priceLabel: 'Free', imageUrl: 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=900&q=80', description: 'Cocuklar ve ebeveynler icin oyun, hikaye ve el isi etkinlikleri.'),
      ];

  @override
  Future<CursorPage<CommunityEvent>> fetchPage({String? cursor, int limit = 20}) async {
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + limit).clamp(0, _events.length).toInt();
    return CursorPage(items: _events.sublist(start, end), nextCursor: end < _events.length ? '$end' : null);
  }

  @override
  Future<List<CommunityEvent>> getUpcomingEvents() async => _events;

  @override
  Future<CommunityEvent> updateRsvp({required String eventId, required EventRsvpStatus status}) async {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index < 0) throw StateError('Etkinlik bulunamadı.');
    final previous = _events[index];
    final attendeeDelta = status == EventRsvpStatus.going && !previous.isGoing ? 1 : status != EventRsvpStatus.going && previous.isGoing ? -1 : 0;
    final updated = previous.copyWith(rsvpStatus: status);
    _events[index] = CommunityEvent(id: updated.id, title: updated.title, category: updated.category, startsAt: updated.startsAt, endsAt: updated.endsAt, location: updated.location, city: updated.city, attendeeCount: updated.attendeeCount + attendeeDelta, priceLabel: updated.priceLabel, imageUrl: updated.imageUrl, description: updated.description, rsvpStatus: updated.rsvpStatus);
    return _events[index];
  }
}
