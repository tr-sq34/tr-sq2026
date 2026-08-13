import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Kabukta sürekli dönen bir gösterge var, `pumpAndSettle` hiç dönmüyor.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> openFeed(WidgetTester tester) async {
  await pumpShell(tester);
  await tapTab(tester, 'Akış');
  await tester.pump();
}

void main() {
  // Üç kısayol da çizilmişti ama hiçbirine dokunulmuyordu. Artık üçü de aynı
  // editörü, kendi işine hazırlanmış hâlde açıyor.
  testWidgets('the Soru Sor shortcut opens the editor set up for a question', (
    tester,
  ) async {
    await openFeed(tester);

    await tester.tap(find.text('Soru Sor'));
    await settle(tester);

    expect(find.text('Soru sor'), findsOneWidget);
    expect(find.text('Topluluğa ne sormak istiyorsun?'), findsOneWidget);
  });

  testWidgets('the Anket shortcut opens the editor with a real poll editor', (
    tester,
  ) async {
    await openFeed(tester);

    await tester.tap(find.text('Anket'));
    await settle(tester);

    expect(find.text('Anket oluştur'), findsOneWidget);
    // İki seçenek hazır geliyor: anket zaten en az ikisiyle kurulabiliyor.
    expect(find.text('1. seçenek'), findsOneWidget);
    expect(find.text('2. seçenek'), findsOneWidget);
  });

  // Eski tabaka "Anket"i metnin sonuna `[Anket]` yazarak taklit ediyordu:
  // kaydedilen bir anket yoktu, oy verilecek bir şey de yoktu.
  testWidgets('a poll is published as a poll, not as bracketed text', (
    tester,
  ) async {
    await openFeed(tester);

    await tester.tap(find.text('Anket'));
    await settle(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Cumartesi nerede buluşalım?');
    await tester.enterText(fields.at(1), 'Brooklyn');
    await tester.enterText(fields.at(2), 'Queens');
    await tester.pump();

    await tester.tap(find.text('Paylaş'));
    await settle(tester);

    expect(find.textContaining('[Anket]'), findsNothing);
    expect(find.text('Cumartesi nerede buluşalım?'), findsOneWidget);
    expect(find.text('Brooklyn'), findsOneWidget);
    expect(find.text('Queens'), findsOneWidget);
    expect(find.text('0 oy'), findsOneWidget);
  });

  testWidgets('voting on the poll shows the distribution that came back', (
    tester,
  ) async {
    await openFeed(tester);

    await tester.tap(find.text('Anket'));
    await settle(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Cumartesi nerede buluşalım?');
    await tester.enterText(fields.at(1), 'Brooklyn');
    await tester.enterText(fields.at(2), 'Queens');
    await tester.pump();
    await tester.tap(find.text('Paylaş'));
    await settle(tester);

    await tester.tap(find.text('Brooklyn'));
    await tester.pump();
    await tester.tap(find.text('Oy ver'));
    await settle(tester);

    // Tek oy verildi: seçilen seçenek %100, diğeri %0. Sayılar depodan
    // dönüyor, kart kendi tahminini göstermiyor.
    expect(find.text('%100'), findsOneWidget);
    expect(find.text('%0'), findsOneWidget);
    expect(find.text('1 oy'), findsOneWidget);
    expect(find.text('Oy ver'), findsNothing);
  });

  // "Herkese Açık" yazan kutu bir etiketti: dokunulunca hiçbir şey açılmıyordu.
  testWidgets('the audience row actually changes who the post goes to', (
    tester,
  ) async {
    await openFeed(tester);

    await tester.tap(find.text('Topluluğa bir şey sor veya paylaş...'));
    await settle(tester);

    await tester.tap(find.text('Herkese Açık'));
    await settle(tester);
    await tester.tap(find.text('Sadece arkadaşlar').last);
    await settle(tester);

    expect(find.text('Sadece arkadaşlar'), findsOneWidget);
    expect(find.text('Herkese Açık'), findsNothing);
  });
}
