import 'package:america_hub/features/safety/presentation/screens/sos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('çekmecenin en üstündeki giriş yardım ekranını açar', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.tap(find.text('Yardım Çağrısı').last);
    await settle(tester);

    expect(find.byType(SosScreen), findsOneWidget);
    // Konum sözü gönderme ekranında yazılı duruyor, bir ayarlar sayfasında
    // değil: üye neyi paylaştığını basmadan önce okuyor.
    expect(find.textContaining('gerekçe yazması gerekir'), findsOneWidget);
    // Ve uygulamanın acil durum hattı olmadığı da orada yazıyor.
    expect(find.textContaining('911'), findsWidgets);
  });

  testWidgets('çağrı onay sormadan gitmez', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    await tester.tap(find.text('Yardım Çağrısı').last);
    await settle(tester);

    // Düğme listenin altında; ekrana getirmeden basmak testin kendi kusuru
    // olur, ekranın değil.
    await tester.ensureVisible(find.text('Yardım İste'));
    await settle(tester);
    await tester.tap(find.text('Yardım İste'));
    await settle(tester);
    expect(find.text('Yardım çağrısı gönderilsin mi?'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await settle(tester);
    // Vazgeçen üye açık bir çağrı bırakmıyor.
    expect(find.textContaining('Çağrın iletildi'), findsNothing);
  });
}
