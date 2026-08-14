import 'package:flutter/material.dart';

/// Çarşı'nın bölümleri.
///
/// [key] sunucuda saklanan değer, [label] ekranda yazan söz. İkisi ayrı, çünkü
/// bir gün "Ev & eşya" yerine başka bir şey yazmak istersek kayıtlı ilanların
/// hiçbirine dokunmamız gerekmesin. Liste kapalı: sunucunun kabul ettiği
/// anahtarlar da bunlar, yoksa hiçbir bölümün açmadığı bir ilan oluşurdu.
enum MarketplaceCategory {
  vehicle('vehicle', 'Araçlar', Icons.directions_car_outlined),
  rental('rental', 'Kiralamalar', Icons.home_outlined),
  home('home', 'Ev & eşya', Icons.chair_outlined),
  electronics('electronics', 'Elektronik', Icons.phone_android_outlined),
  collectible('collectible', 'Koleksiyon', Icons.collections_bookmark_outlined),
  art('art', 'Sanat & hobi', Icons.brush_outlined),
  other('other', 'Diğer', Icons.category_outlined);

  const MarketplaceCategory(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  /// Tanımadığımız bir anahtar gelirse ilan kaybolmuyor, "Diğer" sayılıyor.
  static MarketplaceCategory of(String key) => values.firstWhere(
    (category) => category.key == key,
    orElse: () => MarketplaceCategory.other,
  );

  static String labelOf(String key) => of(key).label;
}
