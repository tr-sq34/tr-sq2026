import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/data/cache/community_page_codec.dart';
import 'package:america_hub/features/community/data/dtos/community_post_dto.dart';
import 'package:america_hub/features/community/data/repositories/api_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> post({
  Object? purpose,
  Object? travelerMatch,
  bool isAuthor = false,
  Object? authorId,
}) => {
  'id': 'post-1',
  'authorId': authorId,
  'authorName': 'Elif Demir',
  'location': 'Queens, NY',
  'createdAtLabel': '2026-08-13T10:00:00.000Z',
  'message': 'Bavulda yer var',
  'likes': 0,
  'comments': 0,
  'isLiked': false,
  'isAuthor': isAuthor,
  'purpose': purpose,
  'travelerMatch': travelerMatch,
};

const _trip = {
  'from': 'İstanbul',
  'to': 'New York',
  'travelAt': '2026-09-01T08:00:00.000Z',
  'packageDetails': '5 kg yer var',
  'note': 'JFK teslim',
};

({ApiCommunityRepository repository, RecordingAdapter adapter}) build(
  List<Object?> bodies,
) {
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
  test('yolculuk paylaşımı rotasıyla birlikte okunuyor', () {
    final domain = CommunityPostDto.fromJson(
      post(purpose: 'travelerMatch', travelerMatch: _trip),
    ).toDomain();

    expect(domain.purpose, CommunityPostPurpose.travelerMatch);
    expect(domain.travelerMatch!.from, 'İstanbul');
    expect(domain.travelerMatch!.to, 'New York');
    expect(domain.travelerMatch!.packageDetails, '5 kg yer var');
    expect(domain.travelerMatch!.note, 'JFK teslim');
  });

  test('amacı olmayan paylaşım sıradan kalıyor', () {
    final domain = CommunityPostDto.fromJson(post()).toDomain();
    expect(domain.purpose, CommunityPostPurpose.standard);
    expect(domain.travelerMatch, isNull);
  });

  test('tanınmayan amaç sıradan sayılıyor, çökmüyor', () {
    final domain = CommunityPostDto.fromJson(
      post(purpose: 'anonymousAdvice'),
    ).toDomain();
    expect(domain.purpose, CommunityPostPurpose.standard);
  });

  test('paylaşımın sahibi sunucudan geliyor', () {
    expect(CommunityPostDto.fromJson(post()).toDomain().isAuthor, isFalse);
    expect(
      CommunityPostDto.fromJson(post(isAuthor: true)).toDomain().isAuthor,
      isTrue,
    );
  });

  test('yazanın kimliği ownerId olarak yerleşiyor', () {
    final domain = CommunityPostDto.fromJson(
      post(authorId: 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
    ).toDomain();
    expect(domain.ownerId, 'cccccccc-cccc-cccc-cccc-cccccccccccc');
  });

  test('kimlik gelmezse eski varsayılan bozulmuyor', () {
    // Sahte kip hâlâ 'local-user' üzerinden çalışıyor; sunucu alanı
    // göndermediğinde o dünyayı bozmuyoruz.
    expect(CommunityPostDto.fromJson(post()).toDomain().ownerId, 'local-user');
  });

  test('yolculuk sunucuya rota, tarih ve paketle gidiyor', () async {
    final harness = build([
      {
        'data': {'id': 'post-1'},
      },
      {
        'data': [post(purpose: 'travelerMatch', travelerMatch: _trip)],
      },
    ]);

    await harness.repository.createPost(
      CreatePostDraft(
        message: 'Bavulda yer var',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.everyone,
        purpose: CommunityPostPurpose.travelerMatch,
        travelerMatch: TravelerMatchDetails(
          from: 'İstanbul',
          to: 'New York',
          travelAt: DateTime.utc(2026, 9, 1, 8),
          packageDetails: '5 kg yer var',
        ),
      ),
    );

    final sent = harness.adapter.requests.first.data as Map<String, dynamic>;
    expect(sent['purpose'], 'traveler_match');
    final trip = sent['travelerMatch'] as Map<String, dynamic>;
    expect(trip['from'], 'İstanbul');
    expect(trip['to'], 'New York');
    expect(trip['travelAt'], '2026-09-01T08:00:00.000Z');
    expect(trip['packageDetails'], '5 kg yer var');
    // Boş not hiç gönderilmiyor: sunucudaki alan "optional", `null` değil.
    expect(trip.containsKey('note'), isFalse);
  });

  test('sıradan paylaşım amaç alanı taşımıyor', () async {
    final harness = build([
      {
        'data': {'id': 'post-1'},
      },
      {
        'data': [post()],
      },
    ]);

    await harness.repository.createPost(
      const CreatePostDraft(
        message: 'Merhaba',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.everyone,
      ),
    );

    final sent = harness.adapter.requests.first.data as Map<String, dynamic>;
    expect(sent.containsKey('purpose'), isFalse);
    expect(sent.containsKey('travelerMatch'), isFalse);
  });

  test('önbellek yolculuğu ve sahipliği koruyor', () {
    final domain = CommunityPostDto.fromJson(
      post(purpose: 'travelerMatch', travelerMatch: _trip, isAuthor: true),
    ).toDomain();
    final codec = CommunityPageCodec();
    final restored = codec.decode(
      codec.encode(CursorPage(items: [domain], nextCursor: null)),
    );

    expect(restored.items.single.purpose, CommunityPostPurpose.travelerMatch);
    expect(restored.items.single.travelerMatch!.to, 'New York');
    expect(restored.items.single.isAuthor, isTrue);
  });
}
