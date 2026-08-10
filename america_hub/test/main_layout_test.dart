import 'package:america_hub/features/home/presentation/widgets/app_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Runs the clock forward far enough for a route transition to finish.
///
/// `pumpAndSettle` is unusable against this shell: the drawer header's dot
/// pulses on a repeating animation, so the tree is never idle and settling
/// times out no matter what is on screen.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  // The menu and the bell used to be arguments handed to the home page alone,
  // so leaving the home tab lost them. They now belong to the shell, and this
  // is what says so.
  testWidgets('the menu and the bell are on every tab', (tester) async {
    await pumpShell(tester);

    final bar = find.byType(AppTopBar);
    for (final tab in ['Ana Sayfa', 'Akış', 'Çarşı', 'Profil']) {
      await tester.tap(find.text(tab));
      await tester.pump();

      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.menu_rounded)),
        findsOneWidget,
        reason: '$tab sekmesinde hamburger yok',
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.byIcon(Icons.notifications_none_rounded),
        ),
        findsOneWidget,
        reason: '$tab sekmesinde bildirim zili yok',
      );
    }
  });

  testWidgets('the hamburger opens the drawer from a tab that is not home', (
    tester,
  ) async {
    await pumpShell(tester, signUpName: 'Zeynep Kaya');

    await tester.tap(find.text('Çarşı'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await settle(tester);

    // Messages live in the drawer and nowhere else, which is the whole reason
    // the top-right icon could become a bell.
    expect(find.text('Mesajlar'), findsOneWidget);
    expect(find.text('Zeynep Kaya'), findsOneWidget);
  });

  testWidgets('the bell shows an honest empty list, not an invented one', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded).first);
    await settle(tester);

    expect(find.text('Henüz bildirim yok'), findsOneWidget);
  });

  testWidgets('the compose button is a shortcut, not a fifth tab', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Profil'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester);
    expect(find.byType(AppTopBar), findsNothing, reason: 'düzenleyici açılmadı');

    // Popped straight from the navigator: the composer's own close affordance
    // is its business, and this test is about the tab underneath it.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);

    // Composing does not move anyone off the tab they were on.
    expect(
      find.descendant(of: find.byType(AppTopBar), matching: find.text('Profil')),
      findsOneWidget,
    );
  });
}
