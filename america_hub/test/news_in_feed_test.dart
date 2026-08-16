import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/community/data/cache/community_page_codec.dart';
import 'package:america_hub/features/community/data/dtos/community_post_dto.dart';
import 'package:america_hub/features/community/presentation/screens/community_screen.dart';
import 'package:america_hub/features/news/presentation/screens/news_article_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Panelden akışa çıkarılan haber, akışta bir paylaşım gibi duruyor.
///
/// Kartın altındaki beğeni ve yorum sayıları haberin kendi sayıları: sunucu
/// ikisini tek yerde tutuyor, o yüzden burada doğrulanacak olan sayının nereden
/// geldiği değil, kartın kim olduğunu doğru söylemesi ve dokunulduğunda habere
/// gitmesi.
Map<String, dynamic> _post({Object? news}) => {
  'id': 'post-1',
  // Sunucu haber satırlarında imzayı kendisi yazıyor; üyenin adı hiç gelmiyor.
  'authorName': news == null ? 'Elif Demir' : 'Haber Bülteni',
  'location': '',
  'createdAtLabel': '2026-08-13T10:00:00.000Z',
  'message': 'Otomatik uzatma süresi 540 güne çıkarıldı.',
  'likes': 61,
  'comments': 14,
  'isLiked': false,
  'news': news,
};

const _newsPayload = {
  'id': 'news-uscis',
  'title': 'USCIS calisma izni suresini uzatti',
  'category': 'gocmenlik',
};

void main() {
  test('haber bağlantısı olan paylaşım bülten kartı sayılıyor', () {
    final domain = CommunityPostDto.fromJson(_post(news: _newsPayload)).toDomain();

    expect(domain.isNewsBulletin, isTrue);
    expect(domain.newsReference!.articleId, 'news-uscis');
    expect(domain.newsReference!.category, 'gocmenlik');
    expect(domain.authorName, 'Haber Bülteni');
  });

  test('sıradan paylaşım bülten kartı değil', () {
    expect(CommunityPostDto.fromJson(_post()).toDomain().isNewsBulletin, isFalse);
  });

  test('kimliği boş gelen haber bağlantısı yok sayılıyor', () {
    // Kimliksiz bir bağlantı, dokunulduğunda hiçbir yere gitmeyen bir kart
    // demek olurdu; kart o zaman sıradan bir paylaşım olarak kalsın.
    final domain = CommunityPostDto.fromJson(
      _post(news: {'id': '', 'title': 'Baslik'}),
    ).toDomain();

    expect(domain.isNewsBulletin, isFalse);
  });

  test('çevrimdışı kopyada haber bağlantısı duruyor', () {
    final original = CommunityPostDto.fromJson(_post(news: _newsPayload)).toDomain();
    final codec = CommunityPageCodec();

    final restored = codec
        .decode(codec.encode(CursorPage(items: [original], nextCursor: null)))
        .items
        .single;

    expect(restored.isNewsBulletin, isTrue);
    expect(restored.newsReference!.articleId, 'news-uscis');
    expect(restored.newsReference!.title, 'USCIS calisma izni suresini uzatti');
  });

  testWidgets('akıştaki haber kartı Haber Bülteni imzasıyla çıkıyor', (
    tester,
  ) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    final card = find.byType(CommunityScreen);
    expect(
      find.descendant(of: card, matching: find.text('Haber Bülteni')),
      findsOneWidget,
    );
    // Kategori ve zaman: kartın altındaki satır bir yer adı değil, çünkü
    // haberin bir mahallesi yok.
    expect(
      find.descendant(of: card, matching: find.text('Göçmenlik · 42 dk önce')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Haberin tamamını oku')),
      findsOneWidget,
    );
  });

  testWidgets('haber kartına dokunmak haberin kendisini açıyor', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    final headline = find.descendant(
      of: find.byType(CommunityScreen),
      matching: find.textContaining('USCIS'),
    );
    await tester.ensureVisible(headline.first);
    await tester.pump();
    await tester.tap(headline.first);
    // pumpAndSettle değil: kabukta sürekli dönen bir gösterge var.
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(NewsArticleScreen), findsOneWidget);
  });

  testWidgets('bültene arkadaşlık isteği gönderilemiyor', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    // Kartın kendi menüsü: arkasında bir üye olmadığı için "Arkadaş ekle"
    // satırı hiç açılmıyor, açılsaydı sunucu zaten reddederdi.
    final menu = find
        .descendant(
          of: find.ancestor(
            of: find.text('Haber Bülteni'),
            matching: find.byType(Row),
          ).last,
          matching: find.byIcon(Icons.more_horiz_rounded),
        )
        .first;
    await tester.ensureVisible(menu);
    await tester.pump();
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Arkadaş ekle'), findsNothing);
    expect(find.text('Şikâyet et'), findsOneWidget);
  });
}
