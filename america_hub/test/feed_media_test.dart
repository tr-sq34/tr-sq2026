import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/data/cache/community_page_codec.dart';
import 'package:america_hub/features/community/data/dtos/community_post_dto.dart';
import 'package:america_hub/features/community/data/repositories/api_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/community/domain/entities/feed_extensions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> post({Object? media, Object? poll}) => {
  'id': 'post-1',
  'authorName': 'Elif Demir',
  'location': 'Queens, NY',
  'createdAtLabel': '2026-08-13T10:00:00.000Z',
  'message': 'Bugün ne yapsak?',
  'likes': 2,
  'comments': 1,
  'isLiked': false,
  'media': media,
  'poll': poll,
};

({ApiCommunityRepository repository, RecordingAdapter adapter}) build(List<Object?> bodies) {
  final adapter = RecordingAdapter.sequence(bodies);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiCommunityRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

void main() {
  test('paylaşımın fotoğrafları sırasıyla okunuyor', () {
    final domain = CommunityPostDto.fromJson(
      post(
        media: [
          {'id': 'm-1', 'type': 'image', 'url': 'https://cdn.test/1', 'thumbnailUrl': 'https://cdn.test/1s'},
          {'id': 'm-2', 'type': 'image', 'url': 'https://cdn.test/2', 'thumbnailUrl': null},
        ],
      ),
    ).toDomain();

    expect(domain.media.map((item) => item.id), ['m-1', 'm-2']);
    expect(domain.media.first.thumbnailUrl, 'https://cdn.test/1s');
    expect(domain.media.last.type, PostMediaType.image);
  });

  test('adresi olmayan medya karta hiç girmiyor', () {
    // Taraması bitmemiş bir görselin imzalı adresi olmuyor; boş bir kutu
    // çizmektense o fotoğraf henüz paylaşımın parçası değil.
    final domain = CommunityPostDto.fromJson(
      post(
        media: [
          {'id': 'm-1', 'type': 'image', 'url': ''},
          {'id': 'm-2', 'type': 'image', 'url': 'https://cdn.test/2'},
        ],
      ),
    ).toDomain();

    expect(domain.media.single.id, 'm-2');
  });

  test('anket seçenekleriyle birlikte geliyor', () {
    final domain = CommunityPostDto.fromJson(
      post(
        poll: {
          'id': 'post-1',
          'selectionMode': 'single',
          'closesAt': '2026-08-20T10:00:00.000Z',
          'options': [
            {'id': 'o-1', 'label': 'Piknik', 'votes': 3, 'selected': true},
            {'id': 'o-2', 'label': 'Sinema', 'votes': 1, 'selected': false},
          ],
        },
      ),
    ).toDomain();

    // Soru ayrı bir alan değil, paylaşımın kendi metni.
    expect(domain.poll!.question, 'Bugün ne yapsak?');
    expect(domain.poll!.options.map((option) => option.label), ['Piknik', 'Sinema']);
    expect(domain.poll!.options.first.votes, 3);
    expect(domain.poll!.selectedOptionIds, {'o-1'});
  });

  test('medyasız paylaşım boş listeyle geliyor', () {
    expect(CommunityPostDto.fromJson(post()).toDomain().media, isEmpty);
    expect(CommunityPostDto.fromJson(post()).toDomain().poll, isNull);
  });

  test('paylaşım gönderilirken medya kimlikleri sunucuya gidiyor', () async {
    final harness = build([
      {'data': {'id': 'post-1'}},
      {'data': [post()], 'meta': {'nextCursor': null}},
    ]);

    await harness.repository.createPost(
      CreatePostDraft(
        message: 'Bugün ne yapsak?',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.everyone,
        media: const [
          PostMedia(id: '11111111-1111-4111-8111-111111111111', type: PostMediaType.image, url: 'https://cdn.test/1'),
          // Yüklemesi bitmemiş, yalnızca cihazda duran öğe: kimliği sunucuda
          // hiçbir şeye karşılık gelmiyor, o yüzden gönderilmiyor.
          PostMedia(id: 'local-2', type: PostMediaType.image, url: '/tmp/2.jpg'),
        ],
      ),
    );

    final body = harness.adapter.requests.first.data! as Map<String, dynamic>;
    expect(body['mediaIds'], ['11111111-1111-4111-8111-111111111111']);
  });

  test('çevrimdışı kopya anketi de saklıyor', () {
    final original = CommunityPostDto.fromJson(
      post(
        media: [
          {'id': 'm-1', 'type': 'image', 'url': 'https://cdn.test/1'},
        ],
        poll: {
          'id': 'post-1',
          'selectionMode': 'multiple',
          'closesAt': '2026-08-20T10:00:00.000Z',
          'options': [
            {'id': 'o-1', 'label': 'Piknik', 'votes': 3, 'selected': true},
            {'id': 'o-2', 'label': 'Sinema', 'votes': 1, 'selected': false},
          ],
        },
      ),
    ).toDomain();

    final codec = CommunityPageCodec();
    final restored = codec
        .decode(codec.encode(CursorPage(items: [original], nextCursor: null)))
        .items
        .single;

    expect(restored.media.single.id, 'm-1');
    expect(restored.poll!.selectionMode, PollSelectionMode.multiple);
    expect(restored.poll!.options.map((option) => option.label), ['Piknik', 'Sinema']);
    expect(restored.poll!.options.first.votes, 3);
    expect(restored.poll!.selectedOptionIds, {'o-1'});
    expect(restored.poll!.endsAt, DateTime.parse('2026-08-20T10:00:00.000Z'));
  });

  test('medyasız paylaşımda alan hiç gönderilmiyor', () async {
    final harness = build([
      {'data': {'id': 'post-1'}},
      {'data': [post()], 'meta': {'nextCursor': null}},
    ]);

    await harness.repository.createPost(
      const CreatePostDraft(
        message: 'Selam',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.everyone,
      ),
    );

    // Boş bir dizi göndermek de bir şey söylemek olurdu; sunucudaki şema alanı
    // isteğe bağlı sayıyor ve `null` isteğe bağlı demek değil.
    expect((harness.adapter.requests.first.data! as Map<String, dynamic>).containsKey('mediaIds'), isFalse);
  });
}
