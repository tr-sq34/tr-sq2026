import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/dtos/marketplace_listing_dto.dart';
import 'package:america_hub/features/marketplace/data/repositories/api_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/domain/repositories/marketplace_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> listing({
  bool isSaved = false,
  bool isLiked = false,
  int likeCount = 0,
  int shareCount = 0,
}) => {
  'id': '11111111-1111-4111-8111-111111111111',
  'sellerId': '22222222-2222-4222-8222-222222222222',
  'title': 'Koltuk takımı',
  'description': 'Az kullanılmış, temiz.',
  'price': 450,
  'location': 'Paterson, NJ',
  'sellerName': 'Elif Demir',
  'imageUrl': '',
  'isSaved': isSaved,
  'isLiked': isLiked,
  'likeCount': likeCount,
  'shareCount': shareCount,
  'createdAt': '2026-08-13T10:00:00.000Z',
};

({ApiMarketplaceRepository repository, RecordingAdapter adapter}) build(
  Object? body,
) {
  final adapter = RecordingAdapter(body);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiMarketplaceRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

/// Denetleyici testleri için ağa çıkmayan depo: ne istendiğini kaydediyor,
/// karşılığında verilen ilanı döndürüyor.
class _StubRepository implements MarketplaceRepository {
  _StubRepository({required this.page, this.answer, this.fails = false});
  final List<MarketplaceListing> page;
  final MarketplaceListing? answer;
  final bool fails;
  final List<(String, String, bool)> calls = [];

  Future<MarketplaceListing> _record(String kind, String id, bool value) async {
    calls.add((kind, id, value));
    if (fails) throw Exception('ağ yok');
    return answer!;
  }

  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({String? cursor, int limit = 20}) async =>
      CursorPage(items: page, nextCursor: null);
  @override
  Future<List<MarketplaceListing>> getListings() async => page;
  @override
  Future<MarketplaceListing> setSaved(String listingId, bool value) => _record('save', listingId, value);
  @override
  Future<MarketplaceListing> setLiked(String listingId, bool value) => _record('like', listingId, value);
  @override
  Future<MarketplaceListing> registerShare(String listingId) => _record('share', listingId, true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MarketplaceListing local({bool isSaved = false, int likeCount = 0, String id = 'l-1'}) =>
    MarketplaceListing(
      id: id,
      title: 'Koltuk',
      category: 'Ev',
      price: 450,
      condition: '',
      location: 'Paterson, NJ',
      sellerName: 'Elif Demir',
      imageUrl: '',
      isSaved: isSaved,
      likeCount: likeCount,
    );

Future<MarketplaceController> loaded(MarketplaceRepository repository) async {
  final controller = MarketplaceController(repository: repository);
  await controller.load();
  return controller;
}

void main() {
  test('ilanın sahibi ve açıklaması okunuyor', () {
    final domain = MarketplaceListingDto.fromJson(
      listing(isLiked: true, likeCount: 4, shareCount: 2),
    ).toDomain();

    expect(domain.sellerId, '22222222-2222-4222-8222-222222222222');
    expect(domain.description, 'Az kullanılmış, temiz.');
    expect(domain.isLiked, isTrue);
    expect(domain.likeCount, 4);
    expect(domain.shareCount, 2);
  });

  test('kaydetme sunucuya durum olarak gidiyor', () async {
    final harness = build({'data': listing(isSaved: true)});

    final result = await harness.repository.setSaved(
      '11111111-1111-4111-8111-111111111111',
      true,
    );

    final request = harness.adapter.requests.single;
    expect(request.method, 'PUT');
    expect(
      request.path,
      '/marketplace/listings/11111111-1111-4111-8111-111111111111/reactions/save',
    );
    expect(request.data, {'enabled': true});
    expect(result.isSaved, isTrue);
  });

  test('paylaşım kendi ucuna gidiyor', () async {
    final harness = build({'data': listing(shareCount: 3)});

    final result = await harness.repository.registerShare(
      '11111111-1111-4111-8111-111111111111',
    );

    expect(harness.adapter.requests.single.method, 'POST');
    expect(
      harness.adapter.requests.single.path,
      '/marketplace/listings/11111111-1111-4111-8111-111111111111/shares',
    );
    expect(result.shareCount, 3);
  });

  test('sayaç sunucunun söylediği sayıya oturuyor', () async {
    // Beğeniyi biz +1 tahmin ediyoruz; bu arada başkaları da beğenmiş olabilir.
    // Cevap gelince ekranda duran sayı sunucunun saydığı sayı oluyor.
    final repository = _StubRepository(
      page: [local(likeCount: 4)],
      answer: local(likeCount: 9),
    );
    final controller = await loaded(repository);

    await controller.toggleLiked('l-1');

    expect(repository.calls.single, ('like', 'l-1', true));
    expect(controller.items.single.likeCount, 9);
  });

  test('ulaşılamayan sunucuda ilan eski haline dönüyor', () async {
    final repository = _StubRepository(page: [local()], fails: true);
    final controller = await loaded(repository);

    await controller.toggleSaved('l-1');

    expect(repository.calls.single, ('save', 'l-1', true));
    expect(controller.items.single.isSaved, isFalse);
  });

  test('kaydedilenler süzgeci yalnızca kaydedilenleri gösteriyor', () async {
    final repository = _StubRepository(
      page: [local(id: 'l-1', isSaved: true), local(id: 'l-2')],
    );
    final controller = await loaded(repository);

    controller.updateFilters(savedOnly: true);
    expect(controller.visibleItems.map((item) => item.id), ['l-1']);

    controller.updateFilters(savedOnly: false);
    expect(controller.visibleItems.length, 2);
  });
}
