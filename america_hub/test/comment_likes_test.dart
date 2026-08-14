import 'package:america_hub/core/state/async_state.dart';
import 'package:america_hub/features/community/application/community_comments_controller.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/repositories/community_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yalnızca beğeni isteğini kaydeden bir depo; istenirse de reddediyor.
class _RecordingComments implements CommunityCommentsRepository {
  _RecordingComments({this.fails = false});

  final bool fails;
  final List<(String, bool)> likes = [];

  @override
  Future<List<CommunityComment>> getComments(String postId) async => [
    CommunityComment(
      id: 'c-1',
      postId: postId,
      authorId: 'u-1',
      authorName: 'Elif Demir',
      message: 'Harika fikir.',
      createdAt: DateTime(2026, 7, 22, 10, 30),
      likes: 2,
    ),
  ];

  @override
  Future<CommunityComment> createComment({required String postId, required String message, String? parentId}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteComment(String commentId) => throw UnimplementedError();

  @override
  Future<void> setCommentLike({required String commentId, required bool liked}) async {
    likes.add((commentId, liked));
    if (fails) throw StateError('ağ yok');
  }
}

CommunityComment only(CommunityCommentsController controller) =>
    (controller.state as AsyncData<List<CommunityComment>>).value.single;

void main() {
  test('beğeni sunucuya gidiyor ve sayı bir artıyor', () async {
    final repository = _RecordingComments();
    final controller = CommunityCommentsController(repository: repository);
    await controller.load('post-1');

    await controller.toggleLike('c-1');

    expect(repository.likes, [('c-1', true)]);
    expect(only(controller).isLiked, isTrue);
    expect(only(controller).likes, 3);
  });

  test('ikinci dokunuş beğeniyi geri alıyor', () async {
    final repository = _RecordingComments();
    final controller = CommunityCommentsController(repository: repository);
    await controller.load('post-1');

    await controller.toggleLike('c-1');
    await controller.toggleLike('c-1');

    // İstek son durumu söylüyor: "bir azalt" değil, "beğenili değil".
    expect(repository.likes, [('c-1', true), ('c-1', false)]);
    expect(only(controller).isLiked, isFalse);
    expect(only(controller).likes, 2);
  });

  test('sunucu almazsa kalp geri dönüyor', () async {
    final repository = _RecordingComments(fails: true);
    final controller = CommunityCommentsController(repository: repository);
    await controller.load('post-1');

    await controller.toggleLike('c-1');

    // Kalp parmağın altında hemen döndü, ama istek düştü: ekranda kalan sayı
    // kimsenin göremeyeceği bir sayı olurdu.
    expect(repository.likes, [('c-1', true)]);
    expect(only(controller).isLiked, isFalse);
    expect(only(controller).likes, 2);
  });

  test('listede olmayan yorum için istek gitmiyor', () async {
    final repository = _RecordingComments();
    final controller = CommunityCommentsController(repository: repository);
    await controller.load('post-1');

    await controller.toggleLike('c-yok');

    expect(repository.likes, isEmpty);
  });
}
