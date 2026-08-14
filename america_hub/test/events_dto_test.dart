import 'package:america_hub/features/events/data/dtos/community_event_dto.dart';
import 'package:america_hub/features/events/domain/entities/community_event.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> payload({String? region, String? rsvp}) => {
  'id': 'event-1',
  'title': 'Simit ve Sohbet',
  'category': 'Buluşma',
  'startsAt': '2026-09-04T23:00:00.000Z',
  'endsAt': '2026-09-05T01:00:00.000Z',
  'location': 'Astoria Park',
  'city': 'Queens',
  'regionCode': region,
  'priceLabel': 'Ücretsiz',
  'imageUrl': 'https://cdn.example/e.jpg',
  'description': 'Kahvaltı ve sohbet.',
  'attendeeCount': 12,
  'rsvpStatus': rsvp,
};

void main() {
  test('şehir ile eyalet tek satırda birleşiyor', () {
    final event = CommunityEventDto.fromJson(payload(region: 'NY')).toDomain();

    // Ekran tek satır çiziyor ve şehir süzgeci bu satıra bakıyor; sunucu ikisini
    // ayrı gönderdiği için birleştirme tek bir yerde duruyor.
    expect(event.city, 'Queens, NY');
    expect(event.location, 'Astoria Park');
  });

  test('eyaleti olmayan etkinlikte başıboş virgül kalmıyor', () {
    expect(CommunityEventDto.fromJson(payload()).toDomain().city, 'Queens');
  });

  test('katılım durumu okunuyor, bilinmeyen değer katılmıyor sayılıyor', () {
    expect(CommunityEventDto.fromJson(payload(rsvp: 'going')).toDomain().rsvpStatus, EventRsvpStatus.going);
    expect(CommunityEventDto.fromJson(payload(rsvp: 'interested')).toDomain().rsvpStatus, EventRsvpStatus.interested);
    // Sunucu bir gün yeni bir durum eklerse, uygulama çökmek yerine "katılmıyor"
    // demeli: yanlış tarafa düşmenin ucuz olanı bu.
    expect(CommunityEventDto.fromJson(payload(rsvp: 'maybe')).toDomain().rsvpStatus, EventRsvpStatus.none);
    expect(CommunityEventDto.fromJson(payload()).toDomain().rsvpStatus, EventRsvpStatus.none);
  });

  test('zamanlar cihazın saatine çevriliyor', () {
    final event = CommunityEventDto.fromJson(payload(region: 'NY')).toDomain();

    expect(event.startsAt.isUtc, isFalse);
    expect(event.startsAt.toUtc(), DateTime.utc(2026, 9, 4, 23));
    expect(event.endsAt!.toUtc(), DateTime.utc(2026, 9, 5, 1));
  });
}
