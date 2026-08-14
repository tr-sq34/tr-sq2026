import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/post_media_upload.dart';
import 'package:america_hub/features/community/domain/repositories/media_upload_repository.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/dtos/marketplace_listing_dto.dart';
import 'package:america_hub/features/marketplace/data/repositories/api_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_seller.dart';
import 'package:america_hub/features/marketplace/domain/repositories/marketplace_repository.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

/// Taramadan geçen tek bir fotoğraf döndüren yükleyici; reddedilen durumu da
/// aynı akıştan veriyor.
class _StubUploads implements MediaUploadRepository {
  _StubUploads({this.rejected = false});
  final bool rejected;
  var count = 0;

  @override
  Stream<MediaUploadProgress> upload(MediaUploadRequest request) async* {
    count++;
    yield MediaUploadProgress(
      localId: request.media.localId,
      status: MediaUploadStatus.uploading,
      fraction: .5,
    );
    if (rejected) {
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.rejected,
        fraction: 0,
        errorMessage: 'Dosya güvenlik doğrulamasını geçemedi.',
      );
      return;
    }
    yield MediaUploadProgress(
      localId: request.media.localId,
      status: MediaUploadStatus.ready,
      fraction: 1,
      media: PostMedia(
        id: 'media-$count',
        type: PostMediaType.image,
        url: 'https://cdn.test/imzali-$count.jpg',
      ),
    );
  }
}

class _StubRepository implements MarketplaceRepository {
  MarketplaceListingDraft? published;

  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({
    String? cursor,
    int limit = 20,
  }) async => const CursorPage(items: [], nextCursor: null);

  @override
  Future<MarketplaceListing> publishListing(
    MarketplaceListingDraft draft,
  ) async {
    published = draft;
    return MarketplaceListing(
      id: 'l-1',
      title: draft.title,
      category: 'Ev',
      price: draft.price ?? 0,
      condition: '',
      location: draft.location,
      sellerName: 'Siz',
      imageUrl: draft.mediaUrls.isEmpty ? '' : draft.mediaUrls.first,
      mediaUrls: draft.mediaUrls,
    );
  }

  @override
  Future<MarketplaceSellerDashboard> getSellerDashboard() async =>
      const MarketplaceSellerDashboard(
        sellerId: 'user-demo',
        activeListings: 0,
        reservedListings: 0,
        soldListings: 0,
        draftListings: 0,
        saves: 0,
        likes: 0,
        shares: 0,
        saves7d: 0,
        likes7d: 0,
        shares7d: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<MarketplaceController> composing(MediaUploadRepository uploads) async {
  final controller = MarketplaceController(
    repository: _StubRepository(),
    mediaUploads: uploads,
  );
  await controller.beginDraft(MarketplaceListingType.item);
  return controller;
}

void main() {
  test('ilanın fotoğrafları sunucudan sırasıyla okunuyor', () {
    final domain = MarketplaceListingDto.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'title': 'Koltuk',
      'price': 450,
      'imageUrl': 'https://cdn.test/bir.jpg',
      'isSaved': false,
      'media': [
        {'id': 'm-1', 'url': 'https://cdn.test/bir.jpg'},
        {'id': 'm-2', 'url': 'https://cdn.test/iki.jpg'},
        // Adresi imzalanamamış bir fotoğraf çizilemez; sessizce düşüyor.
        {'id': 'm-3', 'url': null},
      ],
    }).toDomain();

    expect(domain.mediaUrls, [
      'https://cdn.test/bir.jpg',
      'https://cdn.test/iki.jpg',
    ]);
    expect(domain.imageUrl, 'https://cdn.test/bir.jpg');
  });

  test('fotoğrafı olmayan ilan stok görsel uydurmuyor', () {
    final domain = MarketplaceListingDto.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'title': 'Koltuk',
      'price': 450,
      'imageUrl': '',
      'isSaved': false,
    }).toDomain();

    expect(domain.mediaUrls, isEmpty);
    expect(domain.imageUrl, '');
  });

  test('taraması biten fotoğraf taslağa ekleniyor', () async {
    final controller = await composing(_StubUploads());

    final error = await controller.attachDraftPhoto(
      localUri: '/tmp/bir.jpg',
      fileName: 'bir.jpg',
      sizeBytes: 1200,
    );

    expect(error, isNull);
    expect(controller.draft!.mediaIds, ['media-1']);
    expect(controller.draft!.mediaUrls, ['https://cdn.test/imzali-1.jpg']);
  });

  test('reddedilen fotoğraf taslağa hiç girmiyor', () async {
    final controller = await composing(_StubUploads(rejected: true));

    final error = await controller.attachDraftPhoto(
      localUri: '/tmp/bir.jpg',
      fileName: 'bir.jpg',
      sizeBytes: 1200,
    );

    expect(error, 'Dosya güvenlik doğrulamasını geçemedi.');
    expect(controller.draft!.mediaIds, isEmpty);
    expect(controller.draft!.mediaUrls, isEmpty);
  });

  test('kaldırılan fotoğraf kimliğiyle birlikte gidiyor', () async {
    final controller = await composing(_StubUploads());
    await controller.attachDraftPhoto(
      localUri: '/tmp/bir.jpg',
      fileName: 'bir.jpg',
      sizeBytes: 1200,
    );
    await controller.attachDraftPhoto(
      localUri: '/tmp/iki.jpg',
      fileName: 'iki.jpg',
      sizeBytes: 1200,
    );

    await controller.removeDraftPhoto(0);

    expect(controller.draft!.mediaIds, ['media-2']);
    expect(controller.draft!.mediaUrls, ['https://cdn.test/imzali-2.jpg']);
  });

  test('yayınlanan ilana adres değil kimlik gidiyor', () async {
    final adapter = RecordingAdapter({
      'data': {'id': '11111111-1111-4111-8111-111111111111'},
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
      ..httpClientAdapter = adapter;
    final repository = ApiMarketplaceRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    );

    await repository.publishListing(
      const MarketplaceListingDraft(
        type: MarketplaceListingType.item,
        title: 'Koltuk takımı',
        price: 450,
        description: 'Az kullanılmış, temiz.',
        mediaIds: ['media-1', 'media-2'],
        mediaUrls: ['https://cdn.test/bir.jpg', 'https://cdn.test/iki.jpg'],
      ),
    );

    final data = adapter.requests.single.data as Map<String, dynamic>;
    expect(data['mediaIds'], ['media-1', 'media-2']);
    // İmzalı adresler süreli; sunucuya gitmelerinin bir anlamı yok.
    expect(data.containsKey('mediaUrls'), isFalse);
  });

  test('satis merkezi sayilari sunucudan geliyor', () async {
    final adapter = RecordingAdapter({
      'data': {
        'sellerId': '22222222-2222-4222-8222-222222222222',
        'activeListings': 3,
        'reservedListings': 1,
        'soldListings': 2,
        'draftListings': 0,
        'saves': 11,
        'likes': 4,
        'shares': 2,
        'saves7d': 5,
        'likes7d': 1,
        'shares7d': 0,
        'topListing': {'id': 'l-9', 'title': 'Vintage kilim', 'saves': 7},
      },
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
      ..httpClientAdapter = adapter;
    final repository = ApiMarketplaceRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    );

    final dashboard = await repository.getSellerDashboard();

    expect(adapter.requests.single.path, '/marketplace/me/overview');
    expect(dashboard.sellerId, '22222222-2222-4222-8222-222222222222');
    expect(dashboard.activeListings, 3);
    expect(dashboard.saves, 11);
    expect(dashboard.topListing!.title, 'Vintage kilim');
    expect(dashboard.hasWeeklyActivity, isTrue);
  });

  test('hareketsiz hafta bos gecti diye isaretleniyor', () async {
    final adapter = RecordingAdapter({
      'data': {
        'sellerId': '22222222-2222-4222-8222-222222222222',
        'activeListings': 1,
        'reservedListings': 0,
        'soldListings': 0,
        'draftListings': 0,
        'saves': 0,
        'likes': 0,
        'shares': 0,
        'saves7d': 0,
        'likes7d': 0,
        'shares7d': 0,
        'topListing': null,
      },
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
      ..httpClientAdapter = adapter;
    final repository = ApiMarketplaceRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    );

    final dashboard = await repository.getSellerDashboard();

    expect(dashboard.hasWeeklyActivity, isFalse);
    expect(dashboard.topListing, isNull);
  });
}
