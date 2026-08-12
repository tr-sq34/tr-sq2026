import '../../../auth/domain/entities/app_user.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/repositories/community_repository.dart';

/// Haber yorumlarının çevrimdışı karşılığı.
///
/// Akış yorumlarıyla aynı sözleşmeyi uygular ([ApiNewsCommentsRepository] ile
/// aynı gerekçe), böylece Haber Merkezi mock modda da paylaşılan yorum
/// bileşenini gerçek veriyle gezdirebiliyor.
class MockNewsCommentsRepository implements CommunityCommentsRepository {
  MockNewsCommentsRepository({required this.viewer});

  /// Yorumu kimin imzalayacağı her yazışta oturumdan okunur.
  ///
  /// Depo kendi başına bir isim uydurmuyor: profilde düzelttiğimiz yanlış
  /// kimliğin yorum altında tekrarı olurdu. Oturum uygulama açılırken henüz
  /// yoktur, bu yüzden kullanıcı değil kullanıcıyı veren çağrı tutuluyor.
  final AppUser? Function() viewer;

  final List<CommunityComment> _comments = [
    CommunityComment(
      id: 'news-comment-1',
      postId: 'news-uscis',
      authorId: 'friend-elif',
      authorName: 'Elif Demir',
      message: 'Başvurum beklemede, 540 gün haberi çok işime yaradı.',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  @override
  Future<List<CommunityComment>> getComments(String postId) async => _comments
      .where((comment) => comment.postId == postId && !comment.isDeleted)
      .toList(growable: false);

  @override
  Future<CommunityComment> createComment({
    required String postId,
    required String message,
    String? parentId,
  }) async {
    final normalized = message.trim();
    if (normalized.isEmpty ||
        normalized.length > CommunityComment.maxMessageLength) {
      throw ArgumentError.value(message, 'message', 'Yorum uzunluğu geçersiz.');
    }
    final user = viewer();
    final name = user?.displayName?.trim();
    final comment = CommunityComment(
      id: 'news-comment-${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      authorId: user?.id ?? 'local-user',
      authorName: name != null && name.isNotEmpty
          ? name
          : user?.email.split('@').first ?? 'Üye',
      message: normalized,
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
    _comments[index] = _comments[index].copyWith(
      status: CommentStatus.deleted,
      deletedAt: DateTime.now(),
    );
  }
}
