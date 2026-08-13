import '../../domain/entities/community_post.dart';
import '../../domain/entities/feed_extensions.dart';

class CommunityPostDto {
  const CommunityPostDto({required this.id, required this.authorName, required this.location, required this.createdAtLabel, required this.message, required this.likes, required this.comments, required this.isLiked, this.poll});
  final String id;
  final String authorName;
  final String location;
  final String createdAtLabel;
  final String message;
  final int likes;
  final int comments;
  final bool isLiked;

  /// Anketi olan paylaşımlarda dolu. Anketin ayrı bir soru alanı yok: soru
  /// paylaşımın kendi metni, o yüzden [message] anketin de sorusu.
  final CommunityPoll? poll;

  factory CommunityPostDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorName = author is Map<String, dynamic> ? author['name'] as String? : null;
    final message = json['message'] as String? ?? '';
    return CommunityPostDto(
        id: json['id'] as String,
        authorName: json['authorName'] as String? ?? authorName ?? 'TurkSquare üyesi',
        location: json['location'] as String? ?? '',
        createdAtLabel: json['createdAtLabel'] as String? ?? 'Az önce',
        message: message,
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        comments: (json['comments'] as num?)?.toInt() ?? 0,
        isLiked: json['isLiked'] as bool? ?? false,
        poll: _pollFromJson(json['poll'], message),
      );
  }

  static CommunityPoll? _pollFromJson(Object? raw, String question) {
    if (raw is! Map<String, dynamic>) return null;
    final options = (raw['options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final closesAt = raw['closesAt'] as String?;
    return CommunityPoll(
      id: raw['id'] as String? ?? '',
      question: question,
      selectionMode: raw['selectionMode'] == 'multiple'
          ? PollSelectionMode.multiple
          : PollSelectionMode.single,
      endsAt: closesAt == null ? null : DateTime.tryParse(closesAt),
      options: [
        for (final option in options)
          PollOption(
            id: option['id'] as String,
            label: option['label'] as String? ?? '',
            votes: (option['votes'] as num?)?.toInt() ?? 0,
          ),
      ],
      selectedOptionIds: {
        for (final option in options)
          if (option['selected'] == true) option['id'] as String,
      },
    );
  }

  CommunityPost toDomain() => CommunityPost(id: id, authorName: authorName, location: location, timeLabel: createdAtLabel, message: message, likes: likes, comments: comments, isLiked: isLiked, poll: poll);
}
