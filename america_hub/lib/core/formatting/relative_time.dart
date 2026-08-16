/// Zamanı okunur hale getiren tek yer.
///
/// Sunucu her paylaşımın anını ISO 8601 olarak gönderiyor ve göndermeli:
/// okuyucunun saat dilimini de dilini de bilmiyor. Etiketi kuran taraf
/// uygulama. Akış bunu yapmadığı sürece kartın altında ham damga duruyordu -
/// "2026-08-13T10:00:00.000Z" bir insana hiçbir şey söylemiyor.
///
/// İki biçim var çünkü iki farklı yerde okunuyorlar. Akışta onlarca kart alt
/// alta geçiyor, orada zaman kartın kimliği değil kenar notu: "3dk". Forumda ve
/// haberde satır tek başına duruyor, orada cümle kuruluyor: "3 dk önce".
library;

/// Akıştaki kısa biçim: `15sn`, `3dk`, `2s`, `4gün`, `2hf`, sonra tarih.
String timeAgoCompact(DateTime moment, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(moment);
  // Gelecek tarihli bir damga saat farkından da gelebilir; "-3dk" yazmaktansa
  // paylaşımın yeni olduğunu söylemek doğruya daha yakın.
  if (elapsed.inSeconds < 5) return 'şimdi';
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}sn';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}dk';
  if (elapsed.inHours < 24) return '${elapsed.inHours}s';
  if (elapsed.inDays < 7) return '${elapsed.inDays}gün';
  if (elapsed.inDays < 35) return '${elapsed.inDays ~/ 7}hf';
  return _date(moment);
}

/// Uzun biçim: `8 dk önce`. Forum listesi ve ana sayfadaki şerit bunu kullanıyor.
String timeAgoVerbose(DateTime moment, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(moment);
  if (elapsed.inMinutes < 1) return 'az önce';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} dk önce';
  if (elapsed.inHours < 24) return '${elapsed.inHours} saat önce';
  if (elapsed.inDays < 7) return '${elapsed.inDays} gün önce';
  if (elapsed.inDays < 30) return '${elapsed.inDays ~/ 7} hafta önce';
  return _date(moment);
}

/// Bir ayı geçen her şey artık "kaç gün önce" değil, bir tarih.
String _date(DateTime moment) =>
    '${moment.day.toString().padLeft(2, '0')}.'
    '${moment.month.toString().padLeft(2, '0')}.${moment.year}';
