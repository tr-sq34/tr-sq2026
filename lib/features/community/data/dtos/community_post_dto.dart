import '../../domain/entities/community_post.dart';

class CommunityPostDto {
  const CommunityPostDto({required this.id, required this.authorName, required this.location, required this.createdAtLabel, required this.message, required this.likes, required this.comments, required this.isLiked});
  final String id;
  final String authorName;
  final String location;
  final String createdAtLabel;
  final String message;
  final int likes;
  final int comments;
  final bool isLiked;

  factory CommunityPostDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorName = author is Map<String, dynamic> ? author['name'] as String? : null;
    return CommunityPostDto(
        id: json['id'] as String,
        authorName: json['authorName'] as String? ?? authorName ?? 'TurkSquare üyesi',
        location: json['location'] as String? ?? '',
        createdAtLabel: json['createdAtLabel'] as String? ?? 'Az önce',
        message: json['message'] as String? ?? '',
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        comments: (json['comments'] as num?)?.toInt() ?? 0,
        isLiked: json['isLiked'] as bool? ?? false,
      );
  }

  CommunityPost toDomain() => CommunityPost(id: id, authorName: authorName, location: location, timeLabel: createdAtLabel, message: message, likes: likes, comments: comments, isLiked: isLiked);
}
