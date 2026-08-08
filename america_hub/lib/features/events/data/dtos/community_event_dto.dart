import '../../domain/entities/community_event.dart';

class CommunityEventDto {
  const CommunityEventDto({required this.id, required this.title, required this.category, required this.startsAt, required this.location, required this.city, required this.attendeeCount, required this.priceLabel, required this.imageUrl});
  final String id, title, category, location, city, priceLabel, imageUrl;
  final DateTime startsAt;
  final int attendeeCount;

  factory CommunityEventDto.fromJson(Map<String, dynamic> json) => CommunityEventDto(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'Etkinlik',
        startsAt: DateTime.parse(json['startsAt'] as String),
        location: json['location'] as String? ?? '',
        city: json['city'] as String? ?? '',
        attendeeCount: (json['attendeeCount'] as num?)?.toInt() ?? 0,
        priceLabel: json['priceLabel'] as String? ?? 'Ücretsiz',
        imageUrl: json['imageUrl'] as String? ?? '',
      );

  CommunityEvent toDomain() => CommunityEvent(id: id, title: title, category: category, startsAt: startsAt, location: location, city: city, attendeeCount: attendeeCount, priceLabel: priceLabel, imageUrl: imageUrl);
}
