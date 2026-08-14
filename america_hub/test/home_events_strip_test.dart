import 'package:america_hub/features/events/presentation/screens/events_screen.dart';
import 'package:america_hub/features/home/presentation/screens/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Kabukta sürekli dönen bir gösterge var, `pumpAndSettle` hiç dönmüyor.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> scrollToStrip(WidgetTester tester) async {
  final list = find.byType(ListView).first;
  for (var attempt = 0; attempt < 12; attempt++) {
    if (find.text('YAKLAŞAN ETKİNLİKLER').evaluate().isNotEmpty) return;
    await tester.drag(list, const Offset(0, -400));
    await tester.pump();
  }
  fail('Yaklaşan etkinlikler şeridi bulunamadı.');
}

void main() {
  // Serit iki etkinligi koda yazilmis halde gosteriyordu: "Turk Piknigi 2026"
  // ve "Anadolu Caz Gecesi". Ikisi de veritabaninda hic olmadi ve karta
  // dokunmak hicbir yere gitmiyordu.
  testWidgets('ana sayfadaki serit gercek etkinlikleri gosteriyor', (
    tester,
  ) async {
    await pumpShell(tester);
    await scrollToStrip(tester);

    expect(find.text('Türk Pikniği 2026'), findsNothing);
    expect(find.text('Turkish Summer Picnic'), findsOneWidget);
  });

  testWidgets('karta dokununca etkinligin kendisi aciliyor', (tester) async {
    await pumpShell(tester);
    await scrollToStrip(tester);

    await tester.tap(find.text('Turkish Summer Picnic'));
    await settle(tester);
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });

  // Etkinlikler ekrani uygulamada yaziliydi ama hicbir yerden acilmiyordu.
  testWidgets('tumunu gor Etkinlikler ekranini aciyor', (tester) async {
    await pumpShell(tester);
    await scrollToStrip(tester);

    await tester.tap(find.text('Tümünü gör'));
    await settle(tester);
    expect(find.byType(EventsScreen), findsOneWidget);
  });

  testWidgets('menude Etkinlikler satiri var ve ekrani aciyor', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);

    await tester.tap(find.text('Etkinlikler').last);
    await settle(tester);
    expect(find.byType(EventsScreen), findsOneWidget);
  });

  test('tarih etiketi yakin gunleri gun adiyla degil dogrudan soyluyor', () {
    final now = DateTime(2026, 8, 14, 9);
    expect(eventDateLabel(DateTime(2026, 8, 14, 20), now: now), 'Bugün');
    expect(eventDateLabel(DateTime(2026, 8, 15, 11), now: now), 'Yarın');
    expect(eventDateLabel(DateTime(2026, 8, 29, 20), now: now), '29 Ağustos');
  });
}
