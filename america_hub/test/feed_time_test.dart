import 'package:america_hub/core/formatting/relative_time.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/community/data/cache/community_page_codec.dart';
import 'package:america_hub/features/community/data/dtos/community_post_dto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Akışın altındaki zaman.
///
/// Sunucu ISO 8601 bir an gönderiyor ve kart bunu olduğu gibi yazıyordu:
/// "2026-08-13T10:00:00.000Z". Etiketi kuran taraf uygulama olmalı, çünkü
/// okuyucunun saat dilimini yalnızca o biliyor.
Map<String, dynamic> _post(String createdAtLabel) => {
  'id': 'post-1',
  'authorName': 'Elif Demir',
  'location': 'Queens, NY',
  'createdAtLabel': createdAtLabel,
  'message': 'Bugün ne yapsak?',
  'likes': 0,
  'comments': 0,
  'isLiked': false,
};

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);
  String ago(Duration elapsed) => timeAgoCompact(now.subtract(elapsed), now: now);

  test('kısa biçim saniyeden tarihe kadar', () {
    expect(ago(const Duration(seconds: 2)), 'şimdi');
    expect(ago(const Duration(seconds: 15)), '15sn');
    expect(ago(const Duration(minutes: 3)), '3dk');
    expect(ago(const Duration(hours: 2)), '2s');
    expect(ago(const Duration(days: 4)), '4gün');
    expect(ago(const Duration(days: 16)), '2hf');
    // Bir ayı geçince "kaç hafta önce" bir şey anlatmıyor; tarih anlatıyor.
    expect(ago(const Duration(days: 200)), '26.01.2026');
  });

  test('ileri tarihli damga eksi değer üretmiyor', () {
    // Cihazın saati birkaç saniye ileri olabilir; "-4sn" yazmaktansa
    // paylaşımın yeni olduğunu söylemek doğruya daha yakın.
    expect(timeAgoCompact(now.add(const Duration(seconds: 30)), now: now), 'şimdi');
  });

  test('uzun biçim forumdaki cümleyi koruyor', () {
    expect(timeAgoVerbose(now.subtract(const Duration(minutes: 8)), now: now), '8 dk önce');
    expect(timeAgoVerbose(now.subtract(const Duration(seconds: 20)), now: now), 'az önce');
  });

  test('sunucudan gelen damga ana koda çözülüyor', () {
    final domain = CommunityPostDto.fromJson(_post('2026-08-13T10:00:00.000Z')).toDomain();

    expect(domain.createdAt, DateTime.parse('2026-08-13T10:00:00.000Z').toLocal());
    // Kart artık ham damgayı yazmıyor.
    expect(domain.relativeTime, isNot(contains('T')));
  });

  test('çözülemeyen damga elde ne varsa onu bırakıyor', () {
    // Demo veride ve eski çevrimdışı kopyalarda alan hazır bir etiket olabilir;
    // çözemediğimiz bir şeyi tarih diye uydurmaktansa olduğu gibi gösteriyoruz.
    final domain = CommunityPostDto.fromJson(_post('18 dk önce')).toDomain();

    expect(domain.createdAt, isNull);
    expect(domain.relativeTime, '18 dk önce');
  });

  test('çevrimdışı kopyada etiket değil an saklanıyor', () {
    final original = CommunityPostDto.fromJson(_post('2026-08-13T10:00:00.000Z')).toDomain();
    final codec = CommunityPageCodec();

    final restored = codec
        .decode(codec.encode(CursorPage(items: [original], nextCursor: null)))
        .items
        .single;

    expect(restored.createdAt, original.createdAt);
  });
}
