import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Seçili sekmenin zemini mor, seçili olmayanınki gri.
Color _chipColor(WidgetTester tester, String label) {
  final chip = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return (chip.decoration! as BoxDecoration).color!;
}

void main() {
  const activeChip = Color(0xFF6B54E8);

  testWidgets('the feed moves between tabs with a horizontal swipe', (
    tester,
  ) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    expect(_chipColor(tester, 'Senin İçin'), activeChip);

    // Kart kenarındaki boşluktan sürüklüyoruz: kartın kendi fotoğraf şeridi de
    // yatay kayıyor, ortadan çekince akış değil o şerit hareket ederdi.
    await tester.dragFrom(const Offset(4, 520), const Offset(-300, 0));
    // pumpAndSettle değil: kabukta sürekli dönen bir gösterge var, ekran hiç
    // "durulmuyor".
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(_chipColor(tester, 'Yakınındakiler'), activeChip);
    expect(_chipColor(tester, 'Senin İçin'), isNot(activeChip));
  });

  testWidgets('the tab strip no longer carries a filter button that does '
      'nothing', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    // Şerit hâlâ orada: kaldırılan yalnızca ölü düğme.
    expect(find.text('Takip ettiklerin'), findsOneWidget);
  });

  // Aşağıdayken sekme değiştiren üye, yeni sekmenin ortasında bir yere
  // düşüyordu: Story rayı da editör de ekranın dışında kalıyor, kısa bir liste
  // de boş alan olarak görünüyordu. Ekranda hiçbir şey değişmemiş gibi
  // duruyordu - üyenin bildirdiği "basınca bir şey çıkmıyor" tam olarak buydu.
  testWidgets('sekme degistirmek akisi basa alir', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    final feed = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView).first,
    );
    await tester.dragFrom(const Offset(4, 520), const Offset(0, -240));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(feed.outerController.offset, greaterThan(0));

    await tester.tap(find.text('Takip ettiklerin'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(feed.outerController.offset, 0);
  });

  // Şerit yatay kayan bir satırdı ve üçüncü sekme dar bir telefonda ekranın
  // sağ kenarının dışında kalıyordu: görünmeyen düğmeye basılamıyor, basmayı
  // deneyen üye de hiçbir şey olmadığını görüyordu.
  testWidgets('uc sekme de ekranin icinde duruyor', (tester) async {
    await pumpShell(tester);
    await tapTab(tester, 'Akış');
    await tester.pump();

    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final label in ['Senin İçin', 'Yakınındakiler', 'Takip ettiklerin']) {
      final box = tester.getRect(find.text(label));
      expect(box.left, greaterThanOrEqualTo(0), reason: '$label soldan taşıyor');
      expect(box.right, lessThanOrEqualTo(screen), reason: '$label sağdan taşıyor');
    }

    // Görünür olması yetmez, dokunuşun da varması gerekiyor.
    await tester.tap(find.text('Takip ettiklerin'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_chipColor(tester, 'Takip ettiklerin'), activeChip);
  });
}
