import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/repositories/community_repository.dart';

/// Haber yorumları, akış yorumlarının sözleşmesini paylaşır.
///
/// Kullanıcının isteği net: "yorum yap editör yazı yazma kısmı akışdakiyle
/// birebir aynı olmalı." Aynı ekranı iki kez yazmamanın yolu aynı sözleşmeyi
/// kullanmak; bu yüzden [CommunityCommentsRepository] burada da uygulanıyor ve
/// `postId` yerine haber kimliği geçiyor.
class ApiNewsCommentsRepository implements CommunityCommentsRepository {
  ApiNewsCommentsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<CommunityComment>> getComments(String postId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityNewsComments(postId),
    );
    return (response.data!['data'] as List<dynamic>)
        .map(
          (raw) => _comment(postId, raw as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<CommunityComment> createComment({
    required String postId,
    required String message,
    String? parentId,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityNewsComments(postId),
      data: {'body': message, 'parentId': ?parentId},
    );
    return _comment(postId, response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteComment(String commentId) =>
      _client.delete<void>(ApiEndpoints.communityNewsComment(commentId));

  @override
  Future<void> setCommentLike({
    required String commentId,
    required bool liked,
  }) => _client.put<Map<String, dynamic>>(
    ApiEndpoints.communityNewsCommentLikes(commentId),
    data: {'enabled': liked},
  );

  CommunityComment _comment(String articleId, Map<String, dynamic> json) =>
      CommunityComment(
        id: json['id'] as String,
        postId: articleId,
        authorId: json['authorId'] as String,
        authorName: json['authorName'] as String? ?? 'TurkSquare üyesi',
        message: json['body'] as String,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        parentId: json['parentId'] as String?,
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        isLiked: json['isLiked'] as bool? ?? false,
      );
}
