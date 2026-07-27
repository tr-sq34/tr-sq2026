import 'dart:convert';

import '../../../core/cache/cache_store.dart';
import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/marketplace_listing.dart';
import '../domain/entities/marketplace_seller.dart';
import '../domain/repositories/marketplace_repository.dart';

enum MarketplaceSort { newest, priceLowToHigh, priceHighToLow }
enum MarketplaceFeed { forYou, local }

class MarketplaceController extends PagedController<MarketplaceListing> {
  MarketplaceController({required MarketplaceRepository repository, MarketplaceListingAnalyzer? analyzer, CacheStore? draftStore}) : _repository = repository, _analyzer = analyzer, _draftStore = draftStore, super(dataSource: repository, pageSize: 20);
  final MarketplaceRepository _repository;
  final MarketplaceListingAnalyzer? _analyzer;
  final CacheStore? _draftStore;
  String _query = '';
  String _category = 'all';
  MarketplaceSort _sort = MarketplaceSort.newest;
  MarketplaceFeed _feed = MarketplaceFeed.forYou;
  MarketplaceSellerOverview? overview;
  MarketplaceSellerAnalytics? analytics;
  MarketplaceListingDraft? draft;

  MarketplaceFeed get feed => _feed;
  String get category => _category;
  MarketplaceSort get sort => _sort;
  List<MarketplaceListing> get visibleItems {
    final query = _query.trim().toLowerCase();
    final result = items.where((listing) {
      final matches = query.isEmpty || listing.title.toLowerCase().contains(query) || listing.location.toLowerCase().contains(query) || listing.category.toLowerCase().contains(query);
      final local = _feed != MarketplaceFeed.local || listing.location.contains('New York') || listing.location.contains('Paterson') || listing.location.contains('Jersey');
      return matches && local && (_category == 'all' || listing.category == _category);
    }).toList(growable: false);
    result.sort((a, b) => switch (_sort) { MarketplaceSort.newest => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)), MarketplaceSort.priceLowToHigh => a.price.compareTo(b.price), MarketplaceSort.priceHighToLow => b.price.compareTo(a.price) });
    return result;
  }

  void selectFeed(MarketplaceFeed value) { _feed = value; notifyListeners(); }
  void updateFilters({String? query, String? category, MarketplaceSort? sort}) { _query = query ?? _query; _category = category ?? _category; _sort = sort ?? _sort; notifyListeners(); }
  Future<void> toggleSaved(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    final optimistic = item.copyWith(isSaved: !item.isSaved);
    replaceItems([for (final value in items) if (value.id == listingId) optimistic else value]);
    try { await _repository.setSaved(listingId, optimistic.isSaved); } catch (_) { replaceItems([for (final value in items) if (value.id == listingId) item else value]); }
  }

  Future<void> toggleLiked(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    final optimistic = item.copyWith(isLiked: !item.isLiked, likeCount: item.likeCount + (item.isLiked ? -1 : 1));
    replaceItems([for (final value in items) if (value.id == listingId) optimistic else value]);
    try { await _repository.setLiked(listingId, optimistic.isLiked); } catch (_) { replaceItems([for (final value in items) if (value.id == listingId) item else value]); }
  }

  Future<void> registerShare(String listingId) async {
    final item = items.where((value) => value.id == listingId).firstOrNull;
    if (item == null) return;
    final optimistic = item.copyWith(shareCount: item.shareCount + 1);
    replaceItems([for (final value in items) if (value.id == listingId) optimistic else value]);
    try { await _repository.registerShare(listingId); } catch (_) { replaceItems([for (final value in items) if (value.id == listingId) item else value]); }
  }

  Future<void> loadSellerOverview() async { overview = await _repository.getSellerOverview(); notifyListeners(); }
  Future<void> loadSellerAnalytics() async { analytics = await _repository.getSellerAnalytics(); notifyListeners(); }
  Future<MarketplaceSellerProfile> sellerProfile(String sellerId) => _repository.getSellerProfile(sellerId);
  Future<List<MarketplaceListing>> sellerListings(String sellerId) => _repository.getSellerListings(sellerId);
  Future<void> beginDraft(MarketplaceListingType type) async { draft = MarketplaceListingDraft(type: type); await _restoreDraft(); notifyListeners(); }
  Future<void> updateDraft(MarketplaceListingDraft value) async { draft = value; await _persistDraft(); notifyListeners(); }
  Future<MarketplaceAnalysisSuggestion?> analyzeDraft() async { final value = draft; if (value == null || _analyzer == null) return null; final suggestion = await _analyzer.analyze(type: value.type, mediaUrls: value.mediaUrls); await updateDraft(value.copyWith(title: value.title.isEmpty ? suggestion.title : value.title, category: value.category.isEmpty ? suggestion.category : value.category, price: value.price ?? suggestion.suggestedPrice, description: value.description.isEmpty ? suggestion.description : value.description)); return suggestion; }
  String? validateDraft() { final value = draft; if (value == null) return 'Taslak bulunamadi.'; if (value.title.trim().isEmpty) return 'Baslik zorunludur.'; if (value.price == null || value.price! <= 0) return 'Gecerli bir fiyat girin.'; if (value.type == MarketplaceListingType.vehicle && (value.fields['make'] ?? '').trim().isEmpty) return 'Arac markasi zorunludur.'; if (value.type == MarketplaceListingType.home && (value.fields['propertyType'] ?? '').trim().isEmpty) return 'Mulk turu zorunludur.'; return null; }
  Future<MarketplaceListing?> publishDraft() async { final value = draft; if (value == null || validateDraft() != null) return null; final listing = await _repository.publishListing(value); replaceItems([listing, ...items]); draft = null; await _draftStore?.remove(_draftKey); await loadSellerOverview(); return listing; }
  Future<MarketplaceOffer> createOffer({required String listingId, required double amount}) => _repository.createOffer(listingId: listingId, amount: amount);
  Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount}) => _repository.updateOfferStatus(offerId: offerId, status: status, counterAmount: counterAmount);
  Future<void> _persistDraft() async { final value = draft; if (value == null || _draftStore == null) return; await _draftStore.write(_draftKey, jsonEncode({'type': value.type.name, 'title': value.title, 'price': value.price, 'description': value.description, 'category': value.category, 'location': value.location, 'mediaUrls': value.mediaUrls, 'fields': value.fields, 'hideExactLocation': value.hideExactLocation, 'commentsEnabled': value.commentsEnabled, 'autoReplyEnabled': value.autoReplyEnabled})); }
  Future<void> _restoreDraft() async { final raw = await _draftStore?.read(_draftKey); if (raw == null || draft == null) return; final json = jsonDecode(raw) as Map<String, dynamic>; if (json['type'] != draft!.type.name) return; draft = MarketplaceListingDraft(type: draft!.type, title: json['title'] as String? ?? '', price: (json['price'] as num?)?.toDouble(), description: json['description'] as String? ?? '', category: json['category'] as String? ?? '', location: json['location'] as String? ?? '', mediaUrls: (json['mediaUrls'] as List? ?? const []).cast<String>(), fields: (json['fields'] as Map? ?? const {}).cast<String, String>(), hideExactLocation: json['hideExactLocation'] as bool? ?? true, commentsEnabled: json['commentsEnabled'] as bool? ?? true, autoReplyEnabled: json['autoReplyEnabled'] as bool? ?? false); }
  Future<void> load() => loadInitial();
  static const _draftKey = 'marketplace.listing_draft';
}

extension on Iterable<MarketplaceListing> {
  MarketplaceListing? get firstOrNull => isEmpty ? null : first;
}
