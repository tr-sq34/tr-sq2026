import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

void main() {
  // Every screenshot of the app used to say "Merhaba, Ahmet!" because the name
  // was a string literal — the login response never carried one.
  testWidgets('the greeting uses the name the member signed up with', (
    tester,
  ) async {
    await pumpShell(tester, signUpName: 'Zeynep Kaya');

    expect(find.text('Merhaba, Zeynep! 👋'), findsOneWidget);
    expect(find.textContaining('Ahmet'), findsNothing);
  });

  testWidgets('with no name on the session it falls back to the address', (
    tester,
  ) async {
    await pumpShell(tester);

    // Not a placeholder person: the part before the @ is at least the member's
    // own, and it is what the drawer shows too.
    expect(find.text('Merhaba, uye! 👋'), findsOneWidget);
    expect(find.textContaining('Ahmet'), findsNothing);
  });
}
