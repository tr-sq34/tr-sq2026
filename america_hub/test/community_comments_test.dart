import 'dart:convert';
import 'dart:typed_data';

import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/data/repositories/api_community_comments_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sunucuya gitmeden isteği yakalayan bir taşıyıcı: hangi yola ne gönderildiğini
/// kaydeder, karşılığında hazır gövdeyi döner.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.statusCode = 200});

  final Object? body;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({ApiCommunityCommentsRepository repository, _StubAdapter adapter}) build(
  Object? body, {
  int statusCode = 200,
}) {
  final adapter = _StubAdapter(body, statusCode: statusCode);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiCommunityCommentsRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

void main() {
  test('yorumlar sunucudan okunuyor ve yazan adıyla eşleşiyor', () async {
    final harness = build({
      'data': [
        {
          'id': 'c-1',
          'authorId': 'u-1',
          'authorName': 'Elif Demir',
          'parentId': null,
          'body': 'Harika fikir.',
          'createdAt': '2026-07-22T10:30:00.000Z',
        },
        {
          'id': 'c-2',
          'authorId': 'u-2',
          'authorName': 'Mehmet Kaya',
          'parentId': 'c-1',
          'body': 'Ben de varım.',
          'createdAt': '2026-07-22T10:35:00.000Z',
        },
      ],
    });

    final comments = await harness.repository.getComments('post-1');

    expect(harness.adapter.requests.single.path, '/community/posts/post-1/comments');
    expect(comments.map((c) => c.authorName), ['Elif Demir', 'Mehmet Kaya']);
    // Yanıtlar ekranda ana yorumun altına yerleşiyor; bağı kuran tek alan bu.
    expect(comments.last.parentId, 'c-1');
    // Liste paylaşımın kimliğini taşımıyor, çağıran biliyor.
    expect(comments.first.postId, 'post-1');
    expect(comments.first.createdAt.isUtc, isFalse);
    expect(comments.first.createdAt.toUtc(), DateTime.utc(2026, 7, 22, 10, 30));
  });

  test('yeni yorum sunucunun döndürdüğü satırla ekleniyor', () async {
    final harness = build({
      'data': {
        'id': 'c-9',
        'authorId': 'u-3',
        'authorName': 'Ahmet Yılmaz',
        'parentId': 'c-1',
        'body': 'Katılıyorum.',
        'createdAt': '2026-07-22T11:00:00.000Z',
      },
    });

    final comment = await harness.repository.createComment(
      postId: 'post-1',
      message: 'Katılıyorum.',
      parentId: 'c-1',
    );

    final request = harness.adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.data, {'body': 'Katılıyorum.', 'parentId': 'c-1'});
    // Kimlik ve zaman sunucudan geliyor: yerelde uydurulan bir kimlik, silme
    // isteğinin karşılıksız kalması demekti.
    expect(comment.id, 'c-9');
    expect(comment.authorName, 'Ahmet Yılmaz');
  });

  test('üst yorum yoksa parentId gövdeye hiç yazılmıyor', () async {
    final harness = build({
      'data': {
        'id': 'c-10',
        'authorId': 'u-3',
        'authorName': 'Ahmet Yılmaz',
        'parentId': null,
        'body': 'Merhaba.',
        'createdAt': '2026-07-22T11:05:00.000Z',
      },
    });

    await harness.repository.createComment(postId: 'post-1', message: 'Merhaba.');

    expect(harness.adapter.requests.single.data, {'body': 'Merhaba.'});
  });

  test('silme isteği paylaşımı değil yorumu adresliyor', () async {
    final harness = build(null, statusCode: 204);

    await harness.repository.deleteComment('c-1');

    final request = harness.adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/community/comments/c-1');
  });

  test('adı gelmeyen yorum kimliksiz kalmıyor', () async {
    final harness = build({
      'data': [
        {
          'id': 'c-1',
          'authorId': 'u-1',
          'body': 'Selam.',
          'createdAt': '2026-07-22T10:30:00.000Z',
        },
      ],
    });

    final comments = await harness.repository.getComments('post-1');

    expect(comments.single.authorName, 'TurkSquare üyesi');
  });
}
