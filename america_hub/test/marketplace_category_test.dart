import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/dtos/marketplace_listing_dto.dart';
import 'package:america_hub/features/marketplace/data/repositories/api_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_category.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_seller.dart';
import 'package:america_hub/features/marketplace/domain/repositories/marketplace_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

class _StubRepository implements MarketplaceRepository {
  _StubRepository([this._items = const []]);
  final List<MarketplaceListing> _items;

  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({
    String? cursor,
    int limit = 20,
  }) async => CursorPage(items: _items, nextCursor: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MarketplaceListing _listing(String id, String category, String title) =>
    MarketplaceListing(
      id: id,
      title: title,
      category: category,
      price: 10,
      condition: '',
      location: 'New York, NY',
      sellerName: 'Satıcı',
      imageUrl: '',
    );

void main() {
  test('tanimadigi anahtar geleni kaybetmiyor, Diger sayiyor', () {
    expect(MarketplaceCategory.of('vehicle'), MarketplaceCategory.vehicle);
    expect(MarketplaceCategory.labelOf('vehicle'), 'Araçlar');
    // Sunucuya bir gün yeni bir bölüm eklenirse, eski uygulama ilanı gizlemek
    // yerine "Diğer" bölümünde gösteriyor.
    expect(MarketplaceCategory.labelOf('drone'), 'Diğer');
  });

  test('sunucudan gelen kategori kartta duruyor', () {
    final listing = MarketplaceListingDto.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'title': 'Kanepe',
      'category': 'home',
      'price': 450,
      'isSaved': false,
    }).toDomain();
    expect(listing.category, 'home');
  });

  // Sunucu her ilana 'Diğer' yazdığı sürece bu süzgeç ya hiçbir şey ya her şey
  // döndürüyordu.
  test('bolum secince yalnizca o bolumun ilanlari kaliyor', () async {
    final controller = MarketplaceController(
      repository: _StubRepository([
        _listing('l-1', 'vehicle', 'Sedan'),
        _listing('l-2', 'home', 'Kanepe'),
        _listing('l-3', 'vehicle', 'Motosiklet'),
      ]),
    );
    await controller.loadInitial();

    controller.updateFilters(category: 'vehicle');
    expect(controller.visibleItems.map((item) => item.id), ['l-1', 'l-3']);

    controller.updateFilters(category: 'all');
    expect(controller.visibleItems.length, 3);
  });

  test('arama ekranda yazan sozle eslesiyor, anahtarla degil', () async {
    final controller = MarketplaceController(
      repository: _StubRepository([
        _listing('l-1', 'vehicle', 'Sedan'),
        _listing('l-2', 'home', 'Kanepe'),
      ]),
    );
    await controller.loadInitial();

    controller.updateFilters(query: 'araç');
    expect(controller.visibleItems.map((item) => item.id), ['l-1']);
  });

  test('arac ilani Araclar bolumunde basliyor', () async {
    final controller = MarketplaceController(repository: _StubRepository());
    await controller.beginDraft(MarketplaceListingType.vehicle);
    expect(controller.draft!.category, MarketplaceCategory.vehicle.key);

    await controller.beginDraft(MarketplaceListingType.item);
    expect(controller.draft!.category, MarketplaceCategory.other.key);
  });

  test('secilen bolum sunucuya gidiyor', () async {
    final adapter = RecordingAdapter.sequence([
      {
        'data': {'id': '11111111-1111-4111-8111-111111111111'},
      },
    ]);
    final repository = ApiMarketplaceRepository(
      client: ApiClient(
        baseUrl: 'https://test.local',
        tokenStore: InMemoryTokenStore(),
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );

    await repository.publishListing(
      const MarketplaceListingDraft(
        type: MarketplaceListingType.item,
        title: 'Kanepe',
        description: 'Az kullanılmış üçlü kanepe.',
        price: 450,
        category: 'home',
      ),
    );

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['category'], 'home');
  });
}
