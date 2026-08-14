import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/community_post.dart';
import '../domain/repositories/community_repository.dart';
import '../domain/services/post_access_policy.dart';

class CommunityCommentsController extends ChangeNotifier {
  CommunityCommentsController({required CommunityCommentsRepository repository}) : _repository = repository;

  final CommunityCommentsRepository _repository;
  AsyncState<List<CommunityComment>> _state = const AsyncLoading();
  AsyncState<List<CommunityComment>> get state => _state;
  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  Future<void> load(String postId) async {
    _state = const AsyncLoading();
    notifyListeners();
    try {
      _state = AsyncData(await _repository.getComments(postId));
    } catch (_) {
      _state = const AsyncFailure('Yorumlar yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> addComment({required CommunityPost post, required String viewerId, required bool isFriend, required String message, String? parentId}) async {
    if (!PostAccessPolicy.canComment(post: post, viewerId: viewerId, isFriend: isFriend)) {
      throw StateError('Bu paylaşıma yorum yapma izniniz yok.');
    }
    await submitComment(targetId: post.id, message: message, parentId: parentId);
  }

  /// Erişim politikası çağıranda olan yorumlar için.
  ///
  /// Haber yorumları akışın görünürlük kurallarına tabi değil — haber herkese
  /// açık — ama aynı listeyi, aynı depoyu ve aynı editörü kullanıyor. Politikayı
  /// [addComment] uygular, yazma işini ikisi de buraya bırakır.
  Future<void> submitComment({required String targetId, required String message, String? parentId}) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      final comment = await _repository.createComment(postId: targetId, message: message, parentId: parentId);
      final current = _state;
      if (current is AsyncData<List<CommunityComment>>) {
        _state = AsyncData([...current.value, comment]);
      }
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Yorum beğenisi: önce ekranda, sonra sunucuda.
  ///
  /// Kalp parmağın altında hemen dönüyor çünkü bir beğeni için ağ beklemek
  /// dokunuşu bozuk hissettiriyor. Sunucu isteği almazsa kalp geri alınıyor:
  /// eskiden bu çağrı hiçbir yere gitmiyordu ve sayı ekran kapanınca sıfırdan
  /// başlıyordu, yani yalnızca dokunan kişi için doğru bir sayıydı.
  Future<void> toggleLike(String commentId) async {
    final current = _state;
    if (current is! AsyncData<List<CommunityComment>>) return;
    final index = current.value.indexWhere((comment) => comment.id == commentId);
    if (index == -1) return;
    final liked = !current.value[index].isLiked;
    _state = AsyncData(_withLike(current.value, commentId, liked));
    notifyListeners();
    try {
      await _repository.setCommentLike(commentId: commentId, liked: liked);
    } catch (_) {
      final now = _state;
      if (now is! AsyncData<List<CommunityComment>>) return;
      _state = AsyncData(_withLike(now.value, commentId, !liked));
      notifyListeners();
    }
  }

  /// Değiştirme değil, kurma: iki kez uygulanması sayıyı iki kez oynatmıyor.
  List<CommunityComment> _withLike(List<CommunityComment> comments, String commentId, bool liked) => [
    for (final comment in comments)
      if (comment.id == commentId && comment.isLiked != liked)
        comment.copyWith(isLiked: liked, likes: liked ? comment.likes + 1 : comment.likes - 1)
      else
        comment,
  ];

  Future<void> deleteComment({required CommunityComment comment, required CommunityPost post, required String viewerId}) async {
    if (!PostAccessPolicy.canDeleteComment(comment: comment, post: post, viewerId: viewerId)) {
      throw StateError('Bu yorumu silme izniniz yok.');
    }
    await removeComment(comment);
  }

  /// Silme izni çağıranda olan yorumlar için: haberde kural tek satır, kendi
  /// yorumunu silersin.
  Future<void> removeComment(CommunityComment comment) async {
    await _repository.deleteComment(comment.id);
    final current = _state;
    if (current is AsyncData<List<CommunityComment>>) {
      _state = AsyncData(current.value.where((item) => item.id != comment.id).toList(growable: false));
      notifyListeners();
    }
  }
}
