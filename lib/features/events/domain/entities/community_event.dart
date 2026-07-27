enum EventRsvpStatus { none, going, interested }

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

  bool get isGoing => rsvpStatus == EventRsvpStatus.going;

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
      );
}
