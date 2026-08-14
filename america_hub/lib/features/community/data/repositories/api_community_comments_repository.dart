import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';

/// Akış yorumları.
///
/// Uygulama ilk günden beri yorumları `MockCommunityCommentsRepository` üstünden
/// gösteriyordu: yazılan yorum yalnızca o telefonun belleğinde duruyor, ekran
/// kapanınca kayboluyor, kimse görmüyordu. Sunucudaki uçlar 005'ten beri vardı;
/// eksik olan tek şey buydu.
///
/// Haber yorumlarıyla aynı sözleşmeyi paylaşıyor — aynı liste, aynı editör — o
/// yüzden gövde ve eşleme de birebir aynı biçimde okunuyor.
class ApiCommunityCommentsRepository implements CommunityCommentsRepository {
  ApiCommunityCommentsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<CommunityComment>> getComments(String postId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityPostComments(postId),
    );
    return (response.data!['data'] as List<dynamic>)
        .map((raw) => _comment(postId, raw as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<CommunityComment> createComment({
    required String postId,
    required String message,
    String? parentId,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityPostComments(postId),
      data: {'body': message, 'parentId': ?parentId},
    );
    return _comment(postId, response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteComment(String commentId) =>
      _client.delete<void>(ApiEndpoints.communityPostComment(commentId));

  CommunityComment _comment(String postId, Map<String, dynamic> json) =>
      CommunityComment(
        id: json['id'] as String,
        postId: postId,
        authorId: json['authorId'] as String,
        // Sunucu adı bulamazsa zaten "TurkSquare üyesi" gönderiyor; buradaki
        // karşılık, alanın hiç gelmediği eski bir yanıt için.
        authorName: json['authorName'] as String? ?? 'TurkSquare üyesi',
        message: json['body'] as String,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        parentId: json['parentId'] as String?,
      );
}
