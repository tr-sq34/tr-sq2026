/// [announcement] diğerlerinden bir yönüyle ayrılıyor: metnini uygulama
/// kurmuyor, TurkSquare yetkilisi yazıyor. Bu yüzden başlığı da gövdesi de
/// sunucudan olduğu gibi geliyor ve satıra dokunmak bir paylaşıma değil,
/// duyurunun tam metnine götürüyor.
enum AppNotificationType { specialRequest, friendRequest, postComment, postLike, listingSaved, listingLiked, eventReminder, announcement, system }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.deepLink,
    this.isRead = false,
  });

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final Uri deepLink;
  final bool isRead;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id, type: type, title: title, body: body, createdAt: createdAt, deepLink: deepLink, isRead: isRead ?? this.isRead,
      );
}
