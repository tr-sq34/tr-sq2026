import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';

class MockCommunityCommentsRepository implements CommunityCommentsRepository {
  MockCommunityCommentsRepository({this.currentUserId = 'local-user', this.currentUserName = 'Ahmet Yılmaz'});

  final String currentUserId;
  final String currentUserName;
  final List<CommunityComment> _comments = [
    CommunityComment(
      id: 'comment-1',
      postId: 'post-1',
      authorId: 'friend-elif',
      authorName: 'Elif Demir',
      message: 'Harika fikir, ben de gelmek isterim.',
      createdAt: DateTime(2026, 7, 22, 10, 30),
    ),
  ];

  @override
  Future<List<CommunityComment>> getComments(String postId) async =>
      _comments.where((comment) => comment.postId == postId && !comment.isDeleted).toList(growable: false);

  @override
  Future<CommunityComment> createComment({required String postId, required String message, String? parentId}) async {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty || normalizedMessage.length > CommunityComment.maxMessageLength) {
      throw ArgumentError.value(message, 'message', 'Yorum uzunluğu geçersiz.');
    }
    final comment = CommunityComment(
      id: 'comment-${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      authorId: currentUserId,
      authorName: currentUserName,
      message: normalizedMessage,
      createdAt: DateTime.now(),
      parentId: parentId,
    );
    _comments.add(comment);
    return comment;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    final index = _comments.indexWhere((comment) => comment.id == commentId);
    if (index == -1) throw StateError('Yorum bulunamadı.');
    _comments[index] = _comments[index].copyWith(status: CommentStatus.deleted, deletedAt: DateTime.now());
  }
}
