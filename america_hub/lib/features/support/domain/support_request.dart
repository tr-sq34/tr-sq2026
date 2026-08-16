/// Destek talebi.
///
/// Şikâyet değil: şikâyet başka bir üyeyi işaret ediyor, bu bizi. Menüdeki
/// "Yardım & Destek" satırı bugüne kadar hiçbir yere gitmiyordu; bu, arkasına
/// konan şeyin uygulama tarafındaki karşılığı.
enum SupportTopic { account, safety, marketplace, content, technical, other }

extension SupportTopicWire on SupportTopic {
  String get wire => switch (this) {
    SupportTopic.account => 'account',
    SupportTopic.safety => 'safety',
    SupportTopic.marketplace => 'marketplace',
    SupportTopic.content => 'content',
    SupportTopic.technical => 'technical',
    SupportTopic.other => 'other',
  };

  String get label => switch (this) {
    SupportTopic.account => 'Hesap ve giriş',
    SupportTopic.safety => 'Güvenlik ve taciz',
    SupportTopic.marketplace => 'Çarşı ve ödeme',
    SupportTopic.content => 'İçerik ve moderasyon',
    SupportTopic.technical => 'Teknik sorun',
    SupportTopic.other => 'Diğer',
  };

  String get hint => switch (this) {
    SupportTopic.account => 'Giriş yapamıyorum, hesabım dondu, e-postamı değiştiremiyorum',
    SupportTopic.safety => 'Rahatsız ediliyorum, tehdit alıyorum',
    SupportTopic.marketplace => 'İlan, ihale veya ödemeyle ilgili bir sorun',
    SupportTopic.content => 'Paylaşımım kaldırıldı, bir karara itiraz ediyorum',
    SupportTopic.technical => 'Uygulama hata veriyor, bir şey açılmıyor',
    SupportTopic.other => 'Yukarıdakilerden hiçbiri',
  };

  static SupportTopic fromWire(String value) => SupportTopic.values
      .where((topic) => topic.wire == value)
      .firstOrNull ?? SupportTopic.other;
}

/// Sıranın kimde olduğunu söyleyen alan. "Açık / kapalı" ikilisi bunu
/// gizliyordu: yanıtlanmış ama kapanmamış bir talep de açık görünüyordu ve üye
/// cevabın hâlâ beklendiğini sanıyordu.
enum SupportStatus { open, answered, closed }

extension SupportStatusLabel on SupportStatus {
  String get label => switch (this) {
    SupportStatus.open => 'Yanıt bekleniyor',
    SupportStatus.answered => 'Yanıtlandı',
    SupportStatus.closed => 'Kapandı',
  };

  static SupportStatus fromWire(String value) => switch (value) {
    'answered' => SupportStatus.answered,
    'closed' => SupportStatus.closed,
    _ => SupportStatus.open,
  };
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromStaff,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final bool fromStaff;
  final String body;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: json['id'] as String? ?? '',
    // Sunucu cevabı yazan kişinin adını göndermiyor; muhatap bir çalışan değil,
    // platform. Ekran da öyle yazıyor.
    fromStaff: json['from'] == 'destek',
    body: json['body'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.topic,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastStaffAt,
    required this.closureReason,
    this.messages = const [],
  });

  final String id;
  final SupportTopic topic;
  final String subject;
  final SupportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Destek ekibinin en son yazdığı an. Boşsa talep henüz hiç yanıtlanmamış -
  /// bunu "cevap yok" diye yazmak, sessizliği açıklamaktan iyi.
  final DateTime? lastStaffAt;

  /// Yanıtsız kapatıldıysa gerekçesi. Kapanmanın sebebini söylemeyen bir
  /// kapanış, üyeye hiçbir şey söylememektir.
  final String? closureReason;

  /// Yalnızca tek bir talep okunduğunda dolu. Listede boş: liste yazışmayı
  /// taşımıyor.
  final List<SupportMessage> messages;

  factory SupportRequest.fromJson(Map<String, dynamic> json) => SupportRequest(
    id: json['id'] as String? ?? '',
    topic: SupportTopicWire.fromWire(json['topic'] as String? ?? 'other'),
    subject: json['subject'] as String? ?? '',
    status: SupportStatusLabel.fromWire(json['status'] as String? ?? 'open'),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    lastStaffAt: DateTime.tryParse(json['lastStaffAt'] as String? ?? '')?.toLocal(),
    closureReason: json['closureReason'] as String?,
    messages: (json['messages'] as List<dynamic>? ?? const [])
        .map((item) => SupportMessage.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// Gönderilecek talep. [clientToken] formun kendisiyle birlikte üretiliyor:
/// aynı form iki kez gönderilirse sunucu ikinci talebi açmıyor, birincisini
/// geri veriyor.
class SupportRequestDraft {
  const SupportRequestDraft({
    required this.topic,
    required this.subject,
    required this.body,
    required this.clientToken,
    this.appVersion,
    this.platform,
  });

  final SupportTopic topic;
  final String subject;
  final String body;
  final String clientToken;
  final String? appVersion;
  final String? platform;

  Map<String, dynamic> toJson() => {
    'topic': topic.wire,
    'subject': subject.trim(),
    'body': body.trim(),
    'clientToken': clientToken,
    if (appVersion != null && appVersion!.isNotEmpty) 'appVersion': appVersion,
    if (platform != null) 'platform': platform,
  };
}
