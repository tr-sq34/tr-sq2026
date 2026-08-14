import 'dart:convert';

import '../../../core/cache/cache_store.dart';
import '../../../core/pagination/paged_controller.dart';
import '../../community/domain/entities/community_post.dart';
import '../../community/domain/entities/post_media_upload.dart';
import '../../community/domain/repositories/media_upload_repository.dart';
import '../domain/entities/marketplace_category.dart';
import '../domain/entities/marketplace_listing.dart';
import '../domain/entities/marketplace_seller.dart';
import '../domain/repositories/marketplace_repository.dart';

enum MarketplaceSort { newest, priceLowToHigh, priceHighToLow }
enum MarketplaceFeed { forYou, local }

class MarketplaceController extends PagedController<MarketplaceListing> {
  MarketplaceController({required MarketplaceRepository repository, CacheStore? draftStore, MediaUploadRepository? mediaUploads}) : _repository = repository, _draftStore = draftStore, _mediaUploads = mediaUploads, super(dataSource: repository, pageSize: 20);
  final MarketplaceRepository _repository;

  /// Bildirimden açılan ilan listede olmayabilir; sunucudan tek tek isteniyor.
  Future<MarketplaceListing> getListing(String listingId) =>
      _repository.getListing(listingId);
  final CacheStore? _draftStore;
  final MediaUploadRepository? _mediaUploads;
  String _query = '';
  String _category = 'all';
  MarketplaceSort _sort = MarketplaceSort.newest;
  MarketplaceFeed _feed = MarketplaceFeed.forYou;

  /// "Kaydedilenler" bir sayfa değil, açık bir süzgeç: nereden açıldıysa orada
  /// kalıyor ve üstteki şeritten tek dokunuşla kapanıyor. Kaydettiğini
  /// bulamayan bir üye için kaydetmenin bir anlamı yok.
  bool _savedOnly = false;
  MarketplaceSellerDashboard? dashboard;
  MarketplaceListingDraft? draft;

  MarketplaceFeed get feed => _feed;
  String get category => _category;
  MarketplaceSort get sort => _sort;
  bool get savedOnly => _savedOnly;
  List<MarketplaceListing> get visibleItems {
    final query = _query.trim().toLowerCase();
    final result = items.where((listing) {
        // Arama ekrandaki sözle eşleşiyor, sunucudaki anahtarla değil: kimse
      // "vehicle" yazmıyor, "araç" yazıyor.
      final matches = query.isEmpty || listing.title.toLowerCase().contains(query) || listing.location.toLowerCase().contains(query) || MarketplaceCategory.labelOf(listing.category).toLowerCase().contains(query);
      final local = _feed != MarketplaceFeed.local || listing.location.contains('New York') || listing.location.contains('Paterson') || listing.location.contains('Jersey');
      return matches && local && (_category == 'all' || listing.category == _category) && (!_savedOnly || listing.isSaved);
    }).toList(growable: false);
    result.sort((a, b) => switch (_sort) { MarketplaceSort.newest => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)), MarketplaceSort.priceLowToHigh => a.price.compareTo(b.price), MarketplaceSort.priceHighToLow => b.price.compareTo(a.price) });
    return result;
  }

  void selectFeed(MarketplaceFeed value) { _feed = value; notifyListeners(); }
  void updateFilters({String? query, String? category, MarketplaceSort? sort, bool? savedOnly}) { _query = query ?? _query; _category = category ?? _category; _sort = sort ?? _sort; _savedOnly = savedOnly ?? _savedOnly; notifyListeners(); }
  /// Dokunuş anında görünüyor, sunucunun cevabı gelince yerini gerçeğine
  /// bırakıyor: sayaç bizim tahminimiz değil, kaç kişinin dokunduğu.
  /// Ulaşamazsak ilan eski haline dönüyor, olmamış bir şey olmuş gibi durmuyor.
  Future<void> _applyReaction(String listingId, MarketplaceListing optimistic, Future<MarketplaceListing> Function() send) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    void put(MarketplaceListing value) => replaceItems([for (final current in items) if (current.id == listingId) value else current]);
    put(optimistic);
    try { put(await send()); } catch (_) { put(item); }
  }

  Future<void> toggleSaved(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    final saved = !item.isSaved;
    await _applyReaction(listingId, item.copyWith(isSaved: saved), () => _repository.setSaved(listingId, saved));
  }

  Future<void> toggleLiked(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    final liked = !item.isLiked;
    await _applyReaction(listingId, item.copyWith(isLiked: liked, likeCount: item.likeCount + (liked ? 1 : -1)), () => _repository.setLiked(listingId, liked));
  }

  Future<void> registerShare(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    await _applyReaction(listingId, item.copyWith(shareCount: item.shareCount + 1), () => _repository.registerShare(listingId));
  }

  /// Sayilar okunamazsa panel eski sayilarla kaliyor. Yenile'ye basip aginin
  /// gitmesi, dun dogru olan sayilarin yerine sifir yazilmasi icin bir sebep
  /// degil.
  Future<void> loadSellerDashboard() async { try { dashboard = await _repository.getSellerDashboard(); } catch (_) { return; } notifyListeners(); }
  Future<MarketplaceSellerProfile> sellerProfile(String sellerId) => _repository.getSellerProfile(sellerId);
  Future<List<MarketplaceListing>> sellerListings(String sellerId) => _repository.getSellerListings(sellerId);
  /// Taslak, satıcının seçtiği ilan türüne uyan bölümde başlıyor: "Araç"
  /// seçtiyse bölüm de Araçlar, bu bir tahmin değil aynı sorunun cevabı.
  /// Diğer türlerde tür bölümü belirlemiyor, o yüzden "Diğer" başlıyorlar ve
  /// satıcı düzenleyicide değiştiriyor.
  Future<void> beginDraft(MarketplaceListingType type) async { draft = MarketplaceListingDraft(type: type, category: type == MarketplaceListingType.vehicle ? MarketplaceCategory.vehicle.key : MarketplaceCategory.other.key); await _restoreDraft(); notifyListeners(); }
  Future<void> updateDraft(MarketplaceListingDraft value) async { draft = value; await _persistDraft(); notifyListeners(); }
  String? validateDraft() { final value = draft; if (value == null) return 'Taslak bulunamadi.'; if (value.title.trim().isEmpty) return 'Baslik zorunludur.'; if (value.price == null || value.price! <= 0) return 'Gecerli bir fiyat girin.'; if (value.type == MarketplaceListingType.vehicle && (value.fields['make'] ?? '').trim().isEmpty) return 'Arac markasi zorunludur.'; if (value.type == MarketplaceListingType.home && (value.fields['propertyType'] ?? '').trim().isEmpty) return 'Mulk turu zorunludur.'; return null; }
  /// İlana fotoğraf ekleme. Yükleme akışı Topluluk'takiyle aynı akış: dosya
  /// önce karantinaya çıkıyor, taraması bitene kadar bekleniyor, ancak "ready"
  /// olduğunda taslağa yazılıyor. Böylece yayınlanan ilanda taranmamış bir
  /// dosya bulunmuyor.
  ///
  /// Geriye hata mesajı dönüyor; sorun yoksa null. Yükleme sırasında taslağın
  /// başka alanları değişmiş olabileceği için ekleme her zaman o anki taslağın
  /// üzerine yapılıyor.
  bool get canAttachPhotos => _mediaUploads != null;
  static const maxDraftPhotos = 10;

  Future<String?> attachDraftPhoto({required String localUri, required String fileName, required int sizeBytes, String mimeType = 'image/jpeg'}) async {
    final uploads = _mediaUploads;
    if (uploads == null || draft == null) return 'Fotoğraf eklenemiyor.';
    if (draft!.mediaIds.length >= maxDraftPhotos) return 'En fazla $maxDraftPhotos fotoğraf ekleyebilirsiniz.';
    final request = MediaUploadRequest(
      localUri: localUri,
      media: PostMediaUpload(localId: localUri, type: PostMediaType.image, fileName: fileName, mimeType: mimeType, sizeBytes: sizeBytes),
    );
    try {
      await for (final progress in uploads.upload(request)) {
        final media = progress.media;
        if (progress.status == MediaUploadStatus.ready && media != null) {
          final current = draft;
          if (current == null) return null;
          await updateDraft(current.copyWith(mediaIds: [...current.mediaIds, media.id], mediaUrls: [...current.mediaUrls, media.url]));
          return null;
        }
        if (progress.status == MediaUploadStatus.rejected || progress.status == MediaUploadStatus.failed) {
          return progress.errorMessage ?? 'Fotoğraf yüklenemedi.';
        }
      }
    } catch (_) {
      return 'Fotoğraf yüklenemedi.';
    }
    return 'Fotoğraf yüklenemedi.';
  }

  Future<void> removeDraftPhoto(int index) async {
    final current = draft;
    if (current == null || index < 0 || index >= current.mediaIds.length) return;
    await updateDraft(current.copyWith(
      mediaIds: [...current.mediaIds]..removeAt(index),
      mediaUrls: index < current.mediaUrls.length ? ([...current.mediaUrls]..removeAt(index)) : current.mediaUrls,
    ));
  }

  Future<MarketplaceListing?> publishDraft() async { final value = draft; if (value == null || validateDraft() != null) return null; final listing = await _repository.publishListing(value); replaceItems([listing, ...items]); draft = null; await _draftStore?.remove(_draftKey); await loadSellerDashboard(); return listing; }
  Future<MarketplaceOffer> createOffer({required String listingId, required double amount}) => _repository.createOffer(listingId: listingId, amount: amount);
  Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount}) => _repository.updateOfferStatus(offerId: offerId, status: status, counterAmount: counterAmount);
  Future<void> _persistDraft() async { final value = draft; if (value == null || _draftStore == null) return; await _draftStore.write(_draftKey, jsonEncode({'type': value.type.name, 'title': value.title, 'price': value.price, 'description': value.description, 'category': value.category, 'location': value.location, 'mediaUrls': value.mediaUrls, 'mediaIds': value.mediaIds, 'fields': value.fields, 'hideExactLocation': value.hideExactLocation, 'commentsEnabled': value.commentsEnabled, 'autoReplyEnabled': value.autoReplyEnabled})); }
  Future<void> _restoreDraft() async { final raw = await _draftStore?.read(_draftKey); if (raw == null || draft == null) return; final json = jsonDecode(raw) as Map<String, dynamic>; if (json['type'] != draft!.type.name) return; draft = MarketplaceListingDraft(type: draft!.type, title: json['title'] as String? ?? '', price: (json['price'] as num?)?.toDouble(), description: json['description'] as String? ?? '', category: json['category'] as String? ?? '', location: json['location'] as String? ?? '', mediaUrls: (json['mediaUrls'] as List? ?? const []).cast<String>(), mediaIds: (json['mediaIds'] as List? ?? const []).cast<String>(), fields: (json['fields'] as Map? ?? const {}).cast<String, String>(), hideExactLocation: json['hideExactLocation'] as bool? ?? true, commentsEnabled: json['commentsEnabled'] as bool? ?? true, autoReplyEnabled: json['autoReplyEnabled'] as bool? ?? false); }
  Future<void> load() => loadInitial();
  static const _draftKey = 'marketplace.listing_draft';
}

extension on Iterable<MarketplaceListing> {
  MarketplaceListing? get firstOrNull => isEmpty ? null : first;
}
