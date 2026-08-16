import 'package:america_hub/features/profile/presentation/screens/archive_screen.dart';
import 'package:america_hub/features/profile/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Kabukta sürekli dönen bir gösterge var, `pumpAndSettle` hiç dönmüyor.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> publish(WidgetTester tester, String message) async {
  await tapTab(tester, 'Akış');
  await tester.tap(find.text('Topluluğa bir şey sor veya paylaş...'));
  await settle(tester);
  await tester.enterText(find.byType(TextField).first, message);
  await tester.pump();
  await tester.tap(find.text('Paylaş'));
  await settle(tester);
  // Paylaşımdan sonra çıkan bilgi şeridi alt barın üstünde duruyor: sekmeye
  // dokunmadan önce kendi süresini doldurması gerekiyor.
  await tester.pump(const Duration(seconds: 5));
  await settle(tester);
}

/// Profil ekranındaki metin: akış sekmesi `IndexedStack` içinde canlı kaldığı
/// için aynı paylaşım iki yerde birden bulunabiliyor.
Finder onProfile(String text) =>
    find.descendant(of: find.byType(ProfileScreen), matching: find.text(text));

void main() {
  // Izgara kendi uydurduğu iki kayıttan ibaretti: üye paylaştığı gönderiyi
  // profilinde hiç göremiyordu.
  testWidgets('a published post lands in the profile grid', (tester) async {
    await pumpShell(tester, signUpName: 'Zeynep Kaya');

    await publish(tester, 'Paterson\'da hafta sonu piknik var.');
    await tapTab(tester, 'Profil');
    await settle(tester);
    await tester.tap(find.widgetWithText(Tab, 'Paylaşımlar'));
    await settle(tester);

    expect(onProfile('Paterson\'da hafta sonu piknik var.'), findsOneWidget);
  });

  // Akıştaki başka üyelerin paylaşımları hiçbir zaman "benim" olmamalı.
  testWidgets('the grid holds nobody else\'s posts', (tester) async {
    await pumpShell(tester);

    await tapTab(tester, 'Profil');
    await settle(tester);
    await tester.tap(find.widgetWithText(Tab, 'Paylaşımlar'));
    await settle(tester);

    expect(onProfile('İlk paylaşımını yap.'), findsOneWidget);
  });

  testWidgets('archiving moves the post out of the grid and back', (
    tester,
  ) async {
    await pumpShell(tester, signUpName: 'Zeynep Kaya');

    await publish(tester, 'DMV randevusu sabah 7\'de kolay.');
    await tapTab(tester, 'Profil');
    await settle(tester);
    await tester.tap(find.widgetWithText(Tab, 'Paylaşımlar'));
    await settle(tester);

    await tester.longPress(onProfile('DMV randevusu sabah 7\'de kolay.'));
    await settle(tester);
    await tester.tap(find.text('Arşivle'));
    await settle(tester);

    expect(onProfile('DMV randevusu sabah 7\'de kolay.'), findsNothing);

    // Arşivde duruyor: arşivlemek silmek değil. Arşivin yeri artık ızgaranın
    // üstündeki geçiş değil, çeker menüdeki hesap ayarları.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);
    // Menü uzun; satır ekranın en altında, alt şeridin altında kalıyor.
    await tester.dragFrom(const Offset(150, 600), const Offset(0, -220));
    await settle(tester);
    await tester.tap(find.text('Profil ve Hesap Ayarları').last);
    await settle(tester);
    await tester.tap(find.text('Arşiv'));
    await settle(tester);

    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.text('DMV randevusu sabah 7\'de kolay.'), findsOneWidget);
  });
}
