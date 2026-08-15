/// Ana sayfadaki sponsorlu alan: Story şeridinin başındaki yuva, uygulama içi
/// banner ve "Sana Özel Öne Çıkanlar" kartları.
///
/// Üçü de tek bir kayıt: görsel + başlık + gideceği yer + hedef kitle + tarih
/// aralığı + bir karar. Ayrı sınıflara bölmek, aynı onay akışını üç kez yazmak
/// olurdu; sunucudaki `promotions` tablosu da aynı sebeple tek tablo.
class Promotion {
  const Promotion({
    required this.id,
    required this.placement,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.subtitle,
    this.imageUrl,
    this.targetKind,
    this.targetValue,
    this.regionCode,
    this.city,
    this.decisionReason,
    this.requestNote,
    this.impressions = 0,
    this.clicks = 0,
    this.official = false,
  });

  final String id;
  final PromotionPlacement placement;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final PromotionTargetKind? targetKind;

  /// Hedefin kimliği: gönderi/ilan/haber kimliği ya da harici bir adres.
  final String? targetValue;
  final String? regionCode;
  final String? city;
  final DateTime startsAt;
  final DateTime endsAt;
  final PromotionStatus status;

  /// Reddedilen ya da sonlandırılan talepte operatörün yazdığı gerekçe. Talep
  /// sahibinin neden reddedildiğini okuyamadığı bir kuyruk işe yaramaz.
  final String? decisionReason;

  /// Talebi gönderirken üyenin yazdığı gerekçe; yalnızca kendi listesinde.
  final String? requestNote;
  final int impressions;
  final int clicks;

  /// Kart platformun kendisine mi ait. Kimsenin para ödemediği bir karta
  /// "Sponsorlu" demek üyeye yanlış bilgi vermek; TurkSquare'in kendi kartları
  /// bu yüzden kendi adıyla etiketleniyor.
  final bool official;

  /// Yayında olmak saklanan bir durum değil, saatin aralık içinde olmasıdır.
  /// Sunucu da aynı şeyi söylüyor; burada tekrar hesaplanması, listenin
  /// açıldıktan sonra ekranda beklemesi hâlinde süresi dolanı göstermemek için.
  bool isLiveAt(DateTime now) =>
      status == PromotionStatus.approved &&
      !startsAt.isAfter(now) &&
      endsAt.isAfter(now);

  /// "12.08 - 19.08" — talep listesinde tarih aralığı bu biçimde okunuyor.
  String get windowLabel => '${_day(startsAt)} - ${_day(endsAt)}';

  static String _day(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}';
  }

  /// Hedef kitle satırı; hiçbiri verilmemişse tanıtım ülke geneline çıkar.
  String get audienceLabel {
    if (city != null && regionCode != null) return '$city, $regionCode';
    if (regionCode != null) return regionCode!;
    return 'Amerika geneli';
  }

  factory Promotion.fromJson(Map<String, dynamic> json) => Promotion(
    id: json['id'] as String,
    placement: PromotionPlacement.fromCode(json['placement'] as String?),
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    imageUrl: json['imageUrl'] as String?,
    targetKind: PromotionTargetKind.fromCode(json['targetKind'] as String?),
    targetValue: json['targetValue'] as String?,
    regionCode: json['regionCode'] as String?,
    city: json['city'] as String?,
    startsAt:
        DateTime.tryParse(json['startsAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    endsAt:
        DateTime.tryParse(json['endsAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    status: PromotionStatus.fromCode(json['status'] as String?),
    decisionReason: json['decisionReason'] as String?,
    requestNote: json['requestNote'] as String?,
    impressions: json['impressions'] as int? ?? 0,
    clicks: json['clicks'] as int? ?? 0,
    official: json['official'] as bool? ?? false,
  );
}

/// Sunucudaki `promotions.placement` CHECK listesiyle birebir aynı kodlar.
enum PromotionPlacement {
  storySlot('story_slot', 'Story Alanı Sponsorlu'),
  appBanner('app_banner', 'Uygulama içi Banner'),
  featuredCard('featured_card', 'Öne Çıkan Kart');

  const PromotionPlacement(this.code, this.label);
  final String code;
  final String label;

  /// Üyenin talep edebildikleri. Öne çıkan kart listede yok: o alan editoryal,
  /// yalnızca panelden yerleştiriliyor.
  static const requestable = [storySlot, appBanner];

  static PromotionPlacement fromCode(String? code) =>
      PromotionPlacement.values.firstWhere(
        (placement) => placement.code == code,
        orElse: () => storySlot,
      );
}

enum PromotionStatus {
  pending('pending', 'Onay bekliyor'),
  approved('approved', 'Onaylandı'),
  rejected('rejected', 'Reddedildi'),
  ended('ended', 'Sonlandırıldı');

  const PromotionStatus(this.code, this.label);
  final String code;
  final String label;

  static PromotionStatus fromCode(String? code) =>
      PromotionStatus.values.firstWhere(
        (status) => status.code == code,
        orElse: () => pending,
      );
}

enum PromotionTargetKind {
  post('post'),
  listing('listing'),
  news('news'),
  event('event'),
  external('external');

  const PromotionTargetKind(this.code);
  final String code;

  static PromotionTargetKind? fromCode(String? code) =>
      PromotionTargetKind.values
          .where((kind) => kind.code == code)
          .firstOrNull;
}

/// Ölçüm olayı. Gösterim ve tıklama günlük toplanır; sunucu yalnızca gerçekten
/// yayında olan bir tanıtımı sayar.
enum PromotionEventKind { impression, click }
