import 'dart:convert';
import '../../../../core/cache/cache_codec.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/marketplace_listing.dart';

class MarketplacePageCodec implements CacheCodec<CursorPage<MarketplaceListing>> {
  @override
  CursorPage<MarketplaceListing> decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return CursorPage(items: (data['items'] as List).map((item) { final map = item as Map<String, dynamic>; return MarketplaceListing(id: map['id'], title: map['title'], category: map['category'], price: (map['price'] as num).toDouble(), condition: map['condition'], location: map['location'], sellerName: map['sellerName'], imageUrl: map['imageUrl'], isSaved: map['isSaved']); }).toList(), nextCursor: data['nextCursor']);
  }
  @override
  String encode(CursorPage<MarketplaceListing> value) => jsonEncode({'nextCursor': value.nextCursor, 'items': value.items.map((e) => {'id': e.id, 'title': e.title, 'category': e.category, 'price': e.price, 'condition': e.condition, 'location': e.location, 'sellerName': e.sellerName, 'imageUrl': e.imageUrl, 'isSaved': e.isSaved}).toList()});
}
