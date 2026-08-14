import '../../domain/entities/community_event.dart';

class CommunityEventDto {
  const CommunityEventDto({required this.id, required this.title, required this.category, required this.startsAt, this.endsAt, required this.location, required this.city, required this.attendeeCount, required this.priceLabel, required this.imageUrl, this.description = '', this.rsvpStatus = EventRsvpStatus.none, this.status = EventStatus.published, this.cancellationReason, this.capacity, this.externalUrl, this.interestedCount = 0});
  final String id, title, category, location, city, priceLabel, imageUrl, description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int attendeeCount;
  final EventRsvpStatus rsvpStatus;
  final EventStatus status;
  final String? cancellationReason, externalUrl;
  final int? capacity;
  final int interestedCount;

  factory CommunityEventDto.fromJson(Map<String, dynamic> json) => CommunityEventDto(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'Etkinlik',
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        endsAt: json['endsAt'] == null ? null : DateTime.parse(json['endsAt'] as String).toLocal(),
        location: json['location'] as String? ?? '',
        // Sunucu şehir ile eyaleti ayrı gönderiyor; ekran tek satır gösteriyor
        // ve şehir süzgeci bu satıra bakıyor, o yüzden birleştirme burada.
        city: [json['city'], json['regionCode']].whereType<String>().where((part) => part.isNotEmpty).join(', '),
        attendeeCount: (json['attendeeCount'] as num?)?.toInt() ?? 0,
        priceLabel: json['priceLabel'] as String? ?? 'Ücretsiz',
        imageUrl: json['imageUrl'] as String? ?? '',
        description: json['description'] as String? ?? '',
        rsvpStatus: switch (json['rsvpStatus'] as String?) {
          'going' => EventRsvpStatus.going,
          'interested' => EventRsvpStatus.interested,
          _ => EventRsvpStatus.none,
        },
        // Panelden iptal edilen etkinlik listeden düşüyor ama tek tek okunmaya
        // devam ediyor: takviminde duran kişi 404 değil gerekçe görmeli.
        // Bilinmeyen bir durum "yayında" sayılıyor, çünkü listeye giren her
        // etkinlik zaten yayında olan; taslak buraya hiç ulaşmıyor.
        status: json['status'] == 'cancelled' ? EventStatus.cancelled : EventStatus.published,
        cancellationReason: json['cancellationReason'] as String?,
        // Kapasite ile bilet bağlantısı sunucuda ta ilk günden beri var, panel
        // ikisini de yazıyor; uygulama bugüne kadar ikisini de yok sayıyordu.
        capacity: (json['capacity'] as num?)?.toInt(),
        externalUrl: json['externalUrl'] as String?,
        interestedCount: (json['interestedCount'] as num?)?.toInt() ?? 0,
      );

  CommunityEvent toDomain() => CommunityEvent(id: id, title: title, category: category, startsAt: startsAt, endsAt: endsAt, location: location, city: city, attendeeCount: attendeeCount, priceLabel: priceLabel, imageUrl: imageUrl, description: description, rsvpStatus: rsvpStatus, status: status, cancellationReason: cancellationReason, capacity: capacity, externalUrl: externalUrl, interestedCount: interestedCount);
}
