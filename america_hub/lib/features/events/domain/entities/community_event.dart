enum EventRsvpStatus { none, going, interested }

/// Etkinliğin panelden belirlenen hâli. Taslak olan uygulamaya hiç gelmiyor,
/// o yüzden burada yalnızca iki durum var. İptal edilen etkinliğin satırı
/// sunucuda duruyor: takvimine yazan kişinin akşamı sessizce boşalmasın diye.
enum EventStatus { published, cancelled }

class CommunityEvent {
  const CommunityEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.startsAt,
    required this.location,
    required this.city,
    required this.attendeeCount,
    required this.priceLabel,
    required this.imageUrl,
    this.description = '',
    this.endsAt,
    this.rsvpStatus = EventRsvpStatus.none,
    this.status = EventStatus.published,
    this.cancellationReason,
    this.capacity,
    this.externalUrl,
    this.interestedCount = 0,
  });

  final String id;
  final String title;
  final String category;
  final DateTime startsAt;
  final String location;
  final String city;
  final int attendeeCount;
  final String priceLabel;
  final String imageUrl;
  final String description;
  final DateTime? endsAt;
  final EventRsvpStatus rsvpStatus;
  final EventStatus status;

  /// İptal gerekçesi. Panel iptal ederken zorunlu tutuyor, o yüzden iptal
  /// edilmiş bir etkinlikte pratikte hep dolu geliyor.
  final String? cancellationReason;

  /// Kapı sayısı. Boş olması "sınır yok" demek, sıfır demek değil.
  final int? capacity;

  /// Kayıt burada değilse nereye gidileceği. Sunucu yalnızca https kabul ediyor.
  final String? externalUrl;

  final int interestedCount;

  bool get isGoing => rsvpStatus == EventRsvpStatus.going;
  bool get isCancelled => status == EventStatus.cancelled;

  /// Kalan kontenjan. Kapasitesi olmayan etkinlikte null; dolmuş etkinlikte 0.
  /// Sunucu da aynı sayıyı katılım anında kendisi hesaplıyor, buradaki yalnızca
  /// düğmeye basmadan önce söylenen hâli.
  int? get remainingSeats =>
      capacity == null ? null : (capacity! - attendeeCount).clamp(0, capacity!);

  bool get isFull => remainingSeats == 0;

  CommunityEvent copyWith({EventRsvpStatus? rsvpStatus}) => CommunityEvent(
        id: id,
        title: title,
        category: category,
        startsAt: startsAt,
        location: location,
        city: city,
        attendeeCount: attendeeCount,
        priceLabel: priceLabel,
        imageUrl: imageUrl,
        description: description,
        endsAt: endsAt,
        rsvpStatus: rsvpStatus ?? this.rsvpStatus,
        status: status,
        cancellationReason: cancellationReason,
        capacity: capacity,
        externalUrl: externalUrl,
        interestedCount: interestedCount,
      );
}
