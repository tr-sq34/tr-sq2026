import 'package:america_hub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what each step was asked to do so the tests can assert on the calls
/// themselves, not just on what ended up on screen.
class _ResetSpy {
  final requestedEmails = <String>[];
  final verified = <(String, String)>[];
  final confirmed = <(String, String)>[];
  final completed = <String>[];

  Object? requestError;
  Object? verifyError;
  Object? confirmError;

  Future<void> request(String email) async {
    requestedEmails.add(email);
    if (requestError case final error?) throw error;
  }

  Future<String> verify(String email, String code) async {
    verified.add((email, code));
    if (verifyError case final error?) throw error;
    return 'ticket-1';
  }

  Future<void> confirm(String ticket, String password) async {
    confirmed.add((ticket, password));
    if (confirmError case final error?) throw error;
  }
}

Widget _screen(_ResetSpy spy, {String? initialEmail}) => MaterialApp(
  home: ForgotPasswordScreen(
    initialEmail: initialEmail,
    onRequestReset: spy.request,
    onVerifyCode: spy.verify,
    onConfirmReset: spy.confirm,
    onCompleted: spy.completed.add,
  ),
);

Future<void> _enterCode(WidgetTester tester, String code) async {
  final boxes = find.byType(TextField);
  for (var index = 0; index < code.length; index++) {
    await tester.enterText(boxes.at(index), code[index]);
    await tester.pump();
  }
}

void main() {
  testWidgets('walks email, code and password before resetting', (
    tester,
  ) async {
    final spy = _ResetSpy();
    await tester.pumpWidget(_screen(spy));

    await tester.enterText(find.byType(TextField), 'kisi@example.com');
    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();

    expect(spy.requestedEmails, ['kisi@example.com']);
    expect(find.text('Doğrulama kodunu girin'), findsOneWidget);
    // The address is masked on the code step: a shoulder-surfer should not read
    // the full address off a screen left open.
    expect(
      find.textContaining('ki***@example.com', findRichText: true),
      findsOneWidget,
    );

    await _enterCode(tester, '123456');
    await tester.pumpAndSettle();

    expect(spy.verified, [('kisi@example.com', '123456')]);
    expect(find.text('Yeni parolanızı belirleyin'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'DogruParola2026!');
    await tester.enterText(fields.at(1), 'DogruParola2026!');
    await tester.tap(find.text('Parolayı güncelle'));
    await tester.pumpAndSettle();

    expect(spy.confirmed, [('ticket-1', 'DogruParola2026!')]);
    expect(spy.completed, ['kisi@example.com']);
  });

  testWidgets('offers a resend only once the 59 seconds are up', (
    tester,
  ) async {
    final spy = _ResetSpy();
    await tester.pumpWidget(_screen(spy, initialEmail: 'kisi@example.com'));

    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();

    expect(find.text('Kod 59 saniye daha geçerli.'), findsOneWidget);
    // Resending while a code is still live would invalidate the one the person
    // is in the middle of typing.
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Kodu yeniden gönder'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 59));
    await tester.pumpAndSettle();

    expect(find.text('Kodun süresi doldu.'), findsOneWidget);
    // An expired code cannot be submitted, so the round trip is not even made.
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Doğrula'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Kodu yeniden gönder'));
    await tester.pumpAndSettle();

    expect(spy.requestedEmails.length, 2);
    expect(find.text('Kod 59 saniye daha geçerli.'), findsOneWidget);
  });

  testWidgets('will not submit two passwords that differ', (tester) async {
    final spy = _ResetSpy();
    await tester.pumpWidget(_screen(spy, initialEmail: 'kisi@example.com'));
    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();
    await _enterCode(tester, '123456');
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'DogruParola2026!');
    await tester.enterText(fields.at(1), 'BaskaParola2026!');
    await tester.tap(find.text('Parolayı güncelle'));
    await tester.pumpAndSettle();

    expect(spy.confirmed, isEmpty);
    expect(find.text('Parolalar birbiriyle eşleşmiyor.'), findsOneWidget);
  });

  testWidgets('a password the server rejects sends the person back for a new '
      'code, because the ticket is already spent', (tester) async {
    final spy = _ResetSpy()
      ..confirmError = Exception('Bu parola bilinen veri sızıntılarında yer alıyor.');
    await tester.pumpWidget(_screen(spy, initialEmail: 'kisi@example.com'));
    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();
    await _enterCode(tester, '123456');
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'DogruParola2026!');
    await tester.enterText(fields.at(1), 'DogruParola2026!');
    await tester.tap(find.text('Parolayı güncelle'));
    await tester.pumpAndSettle();

    expect(find.text('Bu parola bilinen veri sızıntılarında yer alıyor.'), findsOneWidget);
    expect(spy.completed, isEmpty);

    // The ticket died with the rejected attempt, so pressing again must not
    // replay it against the server.
    await tester.tap(find.text('Parolayı güncelle'));
    await tester.pumpAndSettle();

    expect(spy.confirmed.length, 1);
    expect(find.text('Parolanızı sıfırlayın'), findsOneWidget);
  });

  testWidgets('a wrong code clears the boxes and never reaches the password '
      'step', (tester) async {
    final spy = _ResetSpy()
      ..verifyError = Exception('Kod geçersiz veya süresi dolmuş.');
    await tester.pumpWidget(_screen(spy, initialEmail: 'kisi@example.com'));
    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();
    await _enterCode(tester, '000000');
    await tester.pumpAndSettle();

    expect(find.text('Kod geçersiz veya süresi dolmuş.'), findsOneWidget);
    expect(find.text('Yeni parolanızı belirleyin'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      isEmpty,
    );
  });

  testWidgets('refuses a malformed address without calling the server', (
    tester,
  ) async {
    final spy = _ResetSpy();
    await tester.pumpWidget(_screen(spy));

    await tester.enterText(find.byType(TextField), 'kisi@');
    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();

    expect(spy.requestedEmails, isEmpty);
    expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
  });
}
