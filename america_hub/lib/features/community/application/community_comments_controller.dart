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
    _isSubmitting = true;
    notifyListeners();
    try {
      final comment = await _repository.createComment(postId: post.id, message: message, parentId: parentId);
      final current = _state;
      if (current is AsyncData<List<CommunityComment>>) {
        _state = AsyncData([...current.value, comment]);
      }
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void toggleLike(String commentId) {
    final current = _state;
    if (current is! AsyncData<List<CommunityComment>>) return;
    _state = AsyncData([for (final comment in current.value) if (comment.id == commentId) comment.copyWith(isLiked: !comment.isLiked, likes: comment.isLiked ? comment.likes - 1 : comment.likes + 1) else comment]);
    notifyListeners();
  }

  Future<void> deleteComment({required CommunityComment comment, required CommunityPost post, required String viewerId}) async {
    if (!PostAccessPolicy.canDeleteComment(comment: comment, post: post, viewerId: viewerId)) {
      throw StateError('Bu yorumu silme izniniz yok.');
    }
    await _repository.deleteComment(comment.id);
    final current = _state;
    if (current is AsyncData<List<CommunityComment>>) {
      _state = AsyncData(current.value.where((item) => item.id != comment.id).toList(growable: false));
      notifyListeners();
    }
  }
}
