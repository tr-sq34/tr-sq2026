import 'package:america_hub/features/events/data/dtos/community_event_dto.dart';
import 'package:america_hub/features/events/domain/entities/community_event.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> payload({
  String? region,
  String? rsvp,
  String? status,
  String? cancellationReason,
  int? capacity,
  String? externalUrl,
  int? interestedCount,
}) => {
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
  'status': status,
  'cancellationReason': cancellationReason,
  'capacity': capacity,
  'externalUrl': externalUrl,
  'interestedCount': interestedCount,
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

  // Sunucu bu dört alanı ilk günden beri gönderiyordu; uygulama dördünü de
  // okumadan atıyordu. Panelden basılan "İptal et" böylece üyeye hiç
  // ulaşmıyor, kontenjanı dolan etkinlikte "Katılacağım" düğmesi açık
  // kalıyor ve etkinliğin kendi bilet sayfası hiçbir yerde görünmüyordu.
  test('iptal, kontenjan ve bilet bağlantısı okunuyor', () {
    final event = CommunityEventDto.fromJson(payload(
      status: 'cancelled',
      cancellationReason: 'Mekan kapandı.',
      capacity: 20,
      externalUrl: 'https://etkinlik.example/bilet',
      interestedCount: 7,
    )).toDomain();

    expect(event.isCancelled, isTrue);
    expect(event.cancellationReason, 'Mekan kapandı.');
    expect(event.capacity, 20);
    expect(event.remainingSeats, 8);
    expect(event.isFull, isFalse);
    expect(event.externalUrl, 'https://etkinlik.example/bilet');
    expect(event.interestedCount, 7);
  });

  test('alanları olmayan etkinlik yayında ve kontenjansız sayılıyor', () {
    final event = CommunityEventDto.fromJson(payload()).toDomain();

    // Listeye giren her etkinlik zaten yayında olan; taslak buraya hiç
    // ulaşmıyor. Bilinmeyen bir durumda ekranı boşaltmak yerine yayında saymak
    // yanlış tarafa düşmenin ucuz olanı.
    expect(event.isCancelled, isFalse);
    expect(event.capacity, isNull);
    expect(event.remainingSeats, isNull);
    expect(event.isFull, isFalse);
    expect(event.externalUrl, isNull);
  });

  test('kontenjanı aşan katılım eksi yer göstermiyor', () {
    final event = CommunityEventDto.fromJson(payload(capacity: 10)).toDomain();

    // Katılan sayısı kontenjanı geçebilir: kapı sayısı yalnızca "going" için
    // uygulanıyor ve kontenjan sonradan düşürülebiliyor.
    expect(event.remainingSeats, 0);
    expect(event.isFull, isTrue);
  });

  test('zamanlar cihazın saatine çevriliyor', () {
    final event = CommunityEventDto.fromJson(payload(region: 'NY')).toDomain();

    expect(event.startsAt.isUtc, isFalse);
    expect(event.startsAt.toUtc(), DateTime.utc(2026, 9, 4, 23));
    expect(event.endsAt!.toUtc(), DateTime.utc(2026, 9, 5, 1));
  });
}
