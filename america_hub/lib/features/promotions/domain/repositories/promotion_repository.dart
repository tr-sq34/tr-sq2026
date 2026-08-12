import '../entities/promotion.dart';

abstract interface class PromotionRepository {
  /// Ana sayfanın okuduğu liste: onaylanmış, saati gelmiş ve bu üyenin
  /// bulunduğu yere açık tanıtımlar. Hedeflemeyi sunucu yapar; istemci gelen
  /// listeyi bir daha elemez.
  Future<List<Promotion>> fetchActive();

  /// Üyenin kendi talepleri, kararları ve sayaçlarıyla birlikte.
  Future<List<Promotion>> fetchMine();

  /// Talep gönderir; dönen kayıt her zaman `pending`. Bu fazda ödeme yok,
  /// talep yalnızca değerlendirilmek üzere kuyruğa düşer.
  Future<void> submit(PromotionRequestDraft draft);

  /// Gösterim ve tıklama sayacı. Sessizce başarısız olması beklenir: ölçüm
  /// kaydedilemedi diye üyeye hata göstermek, kartın kendisini bozmak olurdu.
  Future<void> recordEvent(String promotionId, PromotionEventKind kind);
}

class PromotionRequestDraft {
  const PromotionRequestDraft({
    required this.placement,
    required this.title,
    required this.mediaId,
    required this.startsAt,
    required this.endsAt,
    required this.note,
    this.subtitle,
    this.regionCode,
    this.city,
  });

  final PromotionPlacement placement;
  final String title;
  final String? subtitle;

  /// Yüklenmiş ve güvenlik kontrolünden geçmiş görselin kimliği.
  final String mediaId;
  final DateTime startsAt;
  final DateTime endsAt;

  /// Operatörün kararını verirken okuyacağı gerekçe.
  final String note;
  final String? regionCode;
  final String? city;

  Map<String, dynamic> toJson() => {
    'placement': placement.code,
    'title': title,
    if (subtitle != null && subtitle!.isNotEmpty) 'subtitle': subtitle,
    'mediaId': mediaId,
    // Sunucu UTC ISO-8601 bekliyor; yerel saatle gönderilen aralık, farklı
    // saat diliminden bakan operatörde başka bir gün görünürdü.
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    if (regionCode != null) 'regionCode': regionCode,
    if (city != null && city!.isNotEmpty) 'city': city,
    'note': note,
  };
}
