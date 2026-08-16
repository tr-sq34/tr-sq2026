import '../../domain/entities/app_notification.dart';

/// Sunucudan gelen bildirim satırı.
///
/// Sunucu cümle kurmuyor, olan biteni gönderiyor: hangi tür, hangi konu, kaç
/// kişi. Türkçe metin burada yazılıyor - uygulamanın geri kalanındaki bütün
/// kullanıcıya görünen yazılar gibi.
///
/// [actorName] yalnızca yorumlarda ve isteklerde dolu geliyor. Beğeni ve
/// kaydetme kimseyi adıyla anmıyor: satıcı ilanını kaç kişinin kaydettiğini
/// görüyor, kimlerin kaydettiğini değil. İstek bunun tersi: karşı taraf mesaj
/// yazıp tanışmak istediğini kendisi söylüyor. Sunucu göndermediği yerde burada
/// da uydurulmuyor.
///
/// [body] tek istisna: global duyuruyu bir üye tetiklemiyor, panelden bir
/// yetkili yazıyor. Cümleyi burada kurmak, yazdığı metni yeniden yazmak olurdu.
class AppNotificationDto {
  const AppNotificationDto({
    required this.id,
    required this.kind,
    required this.subjectId,
    required this.subjectTitle,
    required this.body,
    required this.actorCount,
    required this.actorName,
    required this.createdAt,
    required this.isRead,
  });

  factory AppNotificationDto.fromJson(Map<String, dynamic> json) =>
      AppNotificationDto(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        subjectId: json['subjectId'] as String? ?? '',
        subjectTitle: json['subjectTitle'] as String? ?? '',
        body: json['body'] as String?,
        actorCount: (json['actorCount'] as num?)?.toInt() ?? 0,
        actorName: json['actorName'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        isRead: json['isRead'] == true,
      );

  final String id;
  final String kind;
  final String subjectId;
  final String subjectTitle;

  /// Yalnızca duyuruda dolu geliyor; kalan türlerde sunucu cümle göndermiyor.
  final String? body;
  final int actorCount;
  final String? actorName;
  final DateTime createdAt;
  final bool isRead;

  AppNotification toDomain() {
    final type = _typeOf(kind);
    return AppNotification(
      id: id,
      type: type,
      // Duyurunun başlığı da metni de yetkilinin yazdığı gibi kalıyor. Sunucu
      // gövdeyi göndermediyse - eski bir satır ya da silinmiş bir duyuru -
      // başlık tek başına da bir cümle, uydurma bir metinden iyi.
      title: type == AppNotificationType.announcement
          ? (subjectTitle.isEmpty ? 'TurkSquare duyurusu' : subjectTitle)
          : _titleOf(type),
      body: type == AppNotificationType.announcement
          ? (body ?? '')
          : _bodyOf(type),
      createdAt: createdAt,
      deepLink: Uri.parse(switch (type) {
        AppNotificationType.listingSaved ||
        AppNotificationType.listingLiked => 'turksquare://listing/$subjectId',
        // Arkadaşlık isteğinde konu bir paylaşım değil, isteği gönderen üye.
        AppNotificationType.friendRequest => 'turksquare://friend/$subjectId',
        // Duyurunun gideceği bir ekran yok: metnin tamamı bildirim satırının
        // içinde. Bildirimler ekranı bu türü kendisi açıyor, kabuğa göndermiyor.
        AppNotificationType.announcement =>
          'turksquare://announcement/$subjectId',
        // Destek cevabının gideceği yer belli: yazışmanın kendisi.
        AppNotificationType.supportAnswer => 'turksquare://support/$subjectId',
        _ => 'turksquare://post/$subjectId',
      }),
      isRead: isRead,
    );
  }

  static AppNotificationType _typeOf(String kind) => switch (kind) {
    'post_comment' => AppNotificationType.postComment,
    'post_like' => AppNotificationType.postLike,
    'listing_save' => AppNotificationType.listingSaved,
    'listing_like' => AppNotificationType.listingLiked,
    'special_request' => AppNotificationType.specialRequest,
    'friend_request' => AppNotificationType.friendRequest,
    'announcement' => AppNotificationType.announcement,
    'support_answer' => AppNotificationType.supportAnswer,
    _ => AppNotificationType.system,
  };

  static String _titleOf(AppNotificationType type) => switch (type) {
    AppNotificationType.postComment => 'Yeni yorum',
    AppNotificationType.postLike => 'Paylaşımın beğenildi',
    AppNotificationType.listingSaved => 'İlanın kaydedildi',
    AppNotificationType.listingLiked => 'İlanın beğenildi',
    AppNotificationType.specialRequest => 'Yeni istek',
    AppNotificationType.friendRequest => 'Arkadaşlık isteği',
    AppNotificationType.supportAnswer => 'Destek talebin yanıtlandı',
    _ => 'Bildirim',
  };

  String _bodyOf(AppNotificationType type) {
    final subject = _excerpt(subjectTitle);
    return switch (type) {
      AppNotificationType.postComment =>
        actorCount > 1
            ? '${actorName ?? 'Bir üye'} ve ${actorCount - 1} kişi daha '
                  '"$subject" paylaşımına yorum yaptı.'
            : '${actorName ?? 'Bir üye'} "$subject" paylaşımına yorum yaptı.',
      AppNotificationType.postLike =>
        '${_people(actorCount)} "$subject" paylaşımını beğendi.',
      AppNotificationType.listingSaved =>
        '${_people(actorCount)} "$subject" ilanını kaydetti.',
      AppNotificationType.listingLiked =>
        '${_people(actorCount)} "$subject" ilanını beğendi.',
      // Burada sayı bekleyen istek sayısı: sahibi hepsini yanıtladığında satır
      // tamamen kayboluyor, çünkü yapılacak bir şey kalmıyor.
      AppNotificationType.specialRequest =>
        actorCount > 1
            ? '${actorName ?? 'Bir üye'} ve ${actorCount - 1} kişi daha '
                  '"$subject" paylaşımına istek gönderdi.'
            : '${actorName ?? 'Bir üye'} "$subject" paylaşımına istek gönderdi.',
      // Konu başlığı isteği gönderenin adı; sayı ise ondan gelen bekleyen
      // istek sayısı. Yanıtlandığında satır kayboluyor.
      AppNotificationType.friendRequest =>
        '${subject.isEmpty ? 'Bir üye' : subject} sana arkadaşlık isteği gönderdi.',
      // Cevabın kendisi gövdede geliyor; satırda ilk iki satırı görünüyor.
      // Sunucu göndermediyse hiç değilse hangi talep olduğu yazıyor.
      AppNotificationType.supportAnswer =>
        (body == null || body!.trim().isEmpty)
            ? '"$subject" talebine destek ekibi yanıt yazdı.'
            : body!.trim(),
      _ => subject,
    };
  }

  /// Bir kişi "1 kişi" değildir.
  static String _people(int count) => count == 1 ? 'Bir kişi' : '$count kişi';

  /// Bildirim satırı tek satır: uzun bir paylaşımın tamamı buraya sığmıyor.
  static String _excerpt(String value, [int max = 40]) {
    final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max).trim()}…';
  }
}
