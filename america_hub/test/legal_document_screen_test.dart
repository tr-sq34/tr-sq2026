import 'package:america_hub/features/legal/domain/entities/legal_document.dart';
import 'package:america_hub/features/legal/domain/repositories/legal_repository.dart';
import 'package:america_hub/features/legal/presentation/screens/legal_document_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Giriş ekranının altındaki iki bağlantı yıllardır hiçbir yere gitmiyordu.
/// Artık bir ekrana gidiyorlar ve o ekranın üç cevabı var: metin, "henüz
/// yayımlanmadı" ve "okunamadı". Bu dosya üçünün de birbirine karışmadığını
/// sınıyor; çünkü karışırlarsa üye, yazılmamış bir metni bozuk sanır ya da
/// bozuk bir isteği "metin yok" sanır.

class _StubLegalRepository implements LegalRepository {
  _StubLegalRepository(this._answer);

  final Future<LegalDocument> Function(LegalDocumentKind kind) _answer;

  @override
  Future<LegalDocument> getDocument(LegalDocumentKind kind) => _answer(kind);
}

Future<void> _pump(WidgetTester tester, LegalRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LegalDocumentScreen(
        kind: LegalDocumentKind.privacy,
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('published text renders, with "## " lines as headings', (tester) async {
    await _pump(
      tester,
      _StubLegalRepository(
        (kind) async => LegalDocument(
          kind: kind,
          version: 3,
          title: 'Gizlilik Politikası',
          body:
              'Bu metin hangi verinin nerede durduğunu anlatır.\n\n'
              '## Sakladığımız veriler\n\n'
              'Hesabını açarken verdiğin ad ve e-posta adresi.',
          publishedAt: DateTime(2026, 3, 14),
          changeNote: 'Konum verisinin ne zaman toplandigi netlestirildi.',
        ),
      ),
    );

    expect(find.text('Bu metin hangi verinin nerede durduğunu anlatır.'), findsOneWidget);
    // Başlık satırındaki "## " ekranda kalmıyor: panelde yazılan biçim
    // işaretinin üyeye görünmesi, metnin ham hâlini göstermek olurdu.
    expect(find.text('Sakladığımız veriler'), findsOneWidget);
    expect(find.textContaining('## '), findsNothing);

    // Hangi sürümü okuduğu yazıyor; "güncellendi" demek bunun yerine geçmez.
    expect(find.textContaining('Sürüm 3'), findsOneWidget);
    expect(find.textContaining('14.03.2026'), findsOneWidget);
    expect(
      find.textContaining('Konum verisinin ne zaman toplandigi netlestirildi.'),
      findsOneWidget,
    );
  });

  testWidgets('an unpublished document says so instead of showing an empty page', (tester) async {
    await _pump(
      tester,
      _StubLegalRepository(
        (kind) async => throw LegalDocumentNotPublished(kind),
      ),
    );

    expect(find.textContaining('henüz yayımlanmadı'), findsOneWidget);
    // Yeniden denemek işe yarayabilir - yetkili o arada yayımlamış olabilir -
    // ama bu bir arıza değil, o yüzden arıza gibi yazmıyor.
    expect(find.text('Yeniden bak'), findsOneWidget);
    expect(find.textContaining('okunamadı'), findsNothing);
  });

  testWidgets('a read failure names the reason and is not mistaken for missing text', (tester) async {
    await _pump(
      tester,
      _StubLegalRepository((_) async => throw Exception('baglanti kurulamadi')),
    );

    expect(find.textContaining('şu an açılamadı'), findsOneWidget);
    // Sebep ekranda: boşluğun metnin kendisi olmadığını söyleyen tek şey bu.
    expect(find.textContaining('baglanti kurulamadi'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining('henüz yayımlanmadı'), findsNothing);
  });

  testWidgets('the title says which document is loading before the text arrives', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LegalDocumentScreen(
          kind: LegalDocumentKind.terms,
          repository: _StubLegalRepository(
            (kind) => Future<LegalDocument>.delayed(
              const Duration(seconds: 1),
              () => LegalDocument(
                kind: kind,
                version: 1,
                title: 'Kullanım Koşulları',
                body: 'Metin.',
                publishedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Kullanım Koşulları'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Metin.'), findsOneWidget);
  });
}
