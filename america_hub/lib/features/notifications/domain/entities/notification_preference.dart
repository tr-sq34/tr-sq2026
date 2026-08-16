/// Zilde kapatılabilen bildirim türleri.
///
/// Listede duyuru ve destek yanıtı yok, bilerek: biri hesabı ilgilendiren
/// bildirim, diğeri üyenin kendi sorduğu sorunun cevabı. İkisini de
/// kapatılabilir yapmak, üyenin haberi olmadan haberdar olmamasını "tercih"
/// diye kaydetmek olurdu. Ekran bunu gizlemiyor, sebebiyle birlikte yazıyor.
enum NotificationPreferenceKind {
  postComment,
  postLike,
  listingSave,
  listingLike,
  specialRequest,
  friendRequest,
}

extension NotificationPreferenceKindInfo on NotificationPreferenceKind {
  /// Sunucunun bildiği ad. `member_notification_preferences.kind` sütunundaki
  /// CHECK ile birebir aynı; buradaki bir yazım hatası sunucuda 400 döner,
  /// sessizce kaydedilmiş gibi görünmez.
  String get wire => switch (this) {
        NotificationPreferenceKind.postComment => 'post_comment',
        NotificationPreferenceKind.postLike => 'post_like',
        NotificationPreferenceKind.listingSave => 'listing_save',
        NotificationPreferenceKind.listingLike => 'listing_like',
        NotificationPreferenceKind.specialRequest => 'special_request',
        NotificationPreferenceKind.friendRequest => 'friend_request',
      };

  String get label => switch (this) {
        NotificationPreferenceKind.postComment => 'Gönderime yorum',
        NotificationPreferenceKind.postLike => 'Gönderime beğeni',
        NotificationPreferenceKind.listingSave => 'İlanımı kaydedenler',
        NotificationPreferenceKind.listingLike => 'İlanıma beğeni',
        NotificationPreferenceKind.specialRequest => 'Özel istekler',
        NotificationPreferenceKind.friendRequest => 'Arkadaşlık istekleri',
      };

  String get description => switch (this) {
        NotificationPreferenceKind.postComment =>
          'Paylaşımına biri yorum yazdığında.',
        NotificationPreferenceKind.postLike =>
          'Paylaşımın beğenildiğinde. Kimin beğendiği zilde yazmaz.',
        NotificationPreferenceKind.listingSave =>
          'İlanını biri kaydettiğinde. Kimin kaydettiği zilde yazmaz.',
        NotificationPreferenceKind.listingLike =>
          'İlanın beğenildiğinde.',
        NotificationPreferenceKind.specialRequest =>
          'Paylaşımın üzerinden sana ulaşmak isteyen biri olduğunda. Kapatırsan bekleyen isteği yalnızca gönderinde görürsün.',
        NotificationPreferenceKind.friendRequest =>
          'Sana arkadaşlık isteği geldiğinde. Kapatırsan istek yine gelir, zil çalmaz.',
      };
}

/// Türlerin açık/kapalı durumu.
///
/// Sunucu her zaman altı türü de gönderiyor - kaydedilmiş satırı olmayan tür
/// açık sayılıyor - ama burada yine de eksik anahtara karşı [isEnabled] varsayılan
/// olarak açık diyor: eksik bir alan yüzünden üyeye "kapalı" göstermek, hiç
/// dokunmadığı bir ayarı kendisi kapatmış gibi okutur.
class NotificationPreferences {
  const NotificationPreferences(this.values);

  const NotificationPreferences.allEnabled() : values = const {};

  final Map<NotificationPreferenceKind, bool> values;

  bool isEnabled(NotificationPreferenceKind kind) => values[kind] ?? true;

  NotificationPreferences withKind(NotificationPreferenceKind kind, bool enabled) =>
      NotificationPreferences({...values, kind: enabled});

  /// Kapalı tür sayısı; ekrandaki özet satırı bunu yazıyor.
  int get mutedCount =>
      NotificationPreferenceKind.values.where((kind) => !isEnabled(kind)).length;

  factory NotificationPreferences.fromWire(Map<String, dynamic> json) {
    final values = <NotificationPreferenceKind, bool>{};
    for (final kind in NotificationPreferenceKind.values) {
      final value = json[kind.wire];
      if (value is bool) values[kind] = value;
    }
    return NotificationPreferences(values);
  }

  Map<String, bool> toWire() => {
        for (final entry in values.entries) entry.key.wire: entry.value,
      };
}
