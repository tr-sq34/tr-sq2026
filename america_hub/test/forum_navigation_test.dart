import 'package:america_hub/features/forum/presentation/screens/forum_screen.dart';
import 'package:america_hub/features/forum/presentation/screens/forum_topic_screen.dart';
import 'package:america_hub/features/forum/presentation/widgets/forum_topic_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Kabukta sürekli dönen bir gösterge var, `pumpAndSettle` hiç dönmüyor.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  // Çekmecedeki Forum girişi "yakında" etiketiyle duruyordu ve hiçbir yere
  // gitmiyordu.
  testWidgets('the drawer opens the forum', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.tap(find.text('Forum').last);
    await settle(tester);

    expect(find.byType(ForumScreen), findsOneWidget);
    expect(find.byType(ForumTopicCard), findsWidgets);
    // Kilitli kuralları konusu sabit olduğu için listenin başında.
    expect(find.text('Forum kuralları: neyi nereye yazıyoruz?'), findsOneWidget);
  });

  testWidgets('a topic opens with its replies and takes a new one', (
    tester,
  ) async {
    await pumpShell(tester, signUpName: 'Zeynep Kaya');

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.tap(find.text('Forum').last);
    await settle(tester);
    await tester.tap(find.textContaining('NJ ehliyet sınavı'));
    await settle(tester);

    expect(find.byType(ForumTopicScreen), findsOneWidget);
    expect(find.textContaining('6 Puan belgesi'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Bende de öyle oldu.');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester);

    expect(find.text('Bende de öyle oldu.'), findsOneWidget);
    // Yanıt, giriş yapmış üyenin adıyla yazılıyor — uydurma bir imzayla değil.
    expect(find.text('Zeynep Kaya'), findsOneWidget);
  });

  // Kapalı konu okunmaya devam ediyor ama yanıt kutusu yerine sebebi yazıyor.
  testWidgets('a locked topic shows no reply box', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.tap(find.text('Forum').last);
    await settle(tester);
    await tester.tap(find.textContaining('Forum kuralları'));
    await settle(tester);

    expect(find.textContaining('Bu konu kapatıldı'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsNothing);
  });
}
