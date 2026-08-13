/// Üyenin kendi açık yardım çağrısı.
///
/// Burada da koordinat yok — sunucu üyenin kendi çağrısında bile noktayı geri
/// vermiyor, çünkü ekranın onu göstermesi gerekmiyor. Ekranın söylemesi gereken
/// tek şey konumun paylaşıldığı ve şu an kaç yetkilinin ona bakabildiği.
enum SosKind { personalSafety, medical, harassment, accident, other }

extension SosKindWire on SosKind {
  String get wire => switch (this) {
    SosKind.personalSafety => 'personal_safety',
    SosKind.medical => 'medical',
    SosKind.harassment => 'harassment',
    SosKind.accident => 'accident',
    SosKind.other => 'other',
  };

  String get label => switch (this) {
    SosKind.personalSafety => 'Can güvenliği',
    SosKind.medical => 'Sağlık',
    SosKind.harassment => 'Taciz / tehdit',
    SosKind.accident => 'Kaza',
    SosKind.other => 'Diğer',
  };

  String get hint => switch (this) {
    SosKind.personalSafety => 'Tehlikede hissediyorum',
    SosKind.medical => 'Acil sağlık yardımı',
    SosKind.harassment => 'Rahatsız ediliyorum, tehdit alıyorum',
    SosKind.accident => 'Kaza geçirdim',
    SosKind.other => 'Başka bir acil durum',
  };
}

enum SosStatus { active, acknowledged }

class SosAlert {
  const SosAlert({
    required this.id,
    required this.kind,
    required this.status,
    required this.note,
    required this.locationNote,
    required this.locationShared,
    required this.createdAt,
    required this.acknowledgedAt,
    required this.activeLocationWatchers,
  });

  final String id;
  final String kind;
  final SosStatus status;
  final String? note;
  final String? locationNote;
  final bool locationShared;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;

  /// Şu anda konumu görebilen yetkili sayısı. Görüldüğünü bilmeden görülmek,
  /// mührün engellemek için var olduğu şey; o yüzden bu sayı üyeye gösteriliyor.
  final int activeLocationWatchers;

  String get kindLabel =>
      SosKind.values
          .where((value) => value.wire == kind)
          .map((value) => value.label)
          .firstOrNull ??
      'Yardım çağrısı';

  factory SosAlert.fromJson(Map<String, dynamic> json) => SosAlert(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'other',
    status: json['status'] == 'acknowledged'
        ? SosStatus.acknowledged
        : SosStatus.active,
    note: json['note'] as String?,
    locationNote: json['locationNote'] as String?,
    locationShared: json['locationShared'] == true,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    acknowledgedAt: DateTime.tryParse(
      json['acknowledgedAt'] as String? ?? '',
    )?.toLocal(),
    activeLocationWatchers: (json['activeLocationWatchers'] as num?)?.toInt() ?? 0,
  );
}

/// Çağrıyla birlikte gönderilen nokta. Uygulama bunu saklamıyor: alınır,
/// gönderilir, düşer.
class SosPoint {
  const SosPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final int? accuracyMeters;
}

class SosDraft {
  const SosDraft({
    required this.kind,
    this.note,
    this.point,
    this.locationNote,
  });

  final SosKind kind;
  final String? note;
  final SosPoint? point;
  final String? locationNote;

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    if (locationNote != null && locationNote!.trim().isNotEmpty)
      'locationNote': locationNote!.trim(),
    if (point != null) ...{
      'latitude': point!.latitude,
      'longitude': point!.longitude,
      if (point!.accuracyMeters != null)
        'accuracyMeters': point!.accuracyMeters,
    },
  };
}
