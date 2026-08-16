import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ilk ekranda "Google ile devam et", "Apple ile devam et" ve "Telefonla
  // devam et" duruyordu. Ucu de basilinca "yakinda" diyordu; hicbiri hic
  // yazilmadi, kimlik sunucusunda ne OAuth ne telefonla giris var.
  testWidgets('giris ekraninda calismayan giris yolu kalmadi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onCheckEmailStatus: (_) async => true,
          onSignIn: (_, _) async {},
        ),
      ),
    );

    expect(find.text('Google ile devam et'), findsNothing);
    expect(find.text('Apple ile devam et'), findsNothing);
    expect(find.text('Telefonla devam et'), findsNothing);
    // Passkey gercekten calisiyor; o da ancak uygulama saglayinca cikiyor.
    expect(find.text('Passkey ile devam et'), findsNothing);
    expect(find.text('veya'), findsNothing);
  });

  testWidgets('passkey saglandiginda gorunuyor', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onCheckEmailStatus: (_) async => true,
          onSignIn: (_, _) async {},
          onPasskeyLogin: ({String? email}) async => called = true,
        ),
      ),
    );

    expect(find.text('veya'), findsOneWidget);
    await tester.ensureVisible(find.text('Passkey ile devam et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passkey ile devam et'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });

  testWidgets('existing email reveals the password step in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onCheckEmailStatus: (_) async => true,
          onSignIn: (_, _) async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'member@example.com');
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Giriş yap'), findsWidgets);
    expect(find.text('Şifreniz'), findsOneWidget);
    expect(find.text('E-postayı değiştir'), findsOneWidget);
  });

  testWidgets('new email opens registration with the email value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text('Kayıt: ${settings.arguments}')),
        ),
        home: LoginScreen(
          onCheckEmailStatus: (_) async => false,
          onRegisterWithEmail: (email) => Navigator.of(
            tester.element(find.byType(LoginScreen)),
          ).pushNamed('/register', arguments: email),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Kayıt: new@example.com'), findsOneWidget);
  });

  testWidgets('an unverified account is sent to verification, not a dead end', (
    tester,
  ) async {
    String? resumed;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onCheckEmailStatus: (_) async => true,
          onSignIn: (_, _) async => throw const ApiException(
            message: 'E-posta doğrulaması gerekli.',
            statusCode: 403,
            code: 'EMAIL_VERIFICATION_REQUIRED',
          ),
          onVerificationRequired: (email) => resumed = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'pending@example.com');
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'a-password');
    // The password step pushes the button past the default 800x600 surface.
    final signIn = find.widgetWithText(FilledButton, 'Giriş yap');
    await tester.ensureVisible(signIn);
    await tester.pumpAndSettle();
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(resumed, 'pending@example.com');
    // The failure must not also surface as a snack bar the person has to read
    // and dismiss on a screen they have already been moved away from.
    expect(find.text('E-posta doğrulaması gerekli.'), findsNothing);
  });

  // "Devam ederek Kullanim Kosullari ve Gizlilik Politikasi'ni kabul etmis
  // olursunuz" cumlesindeki iki baglantinin da alti ciziliydi ve ikisi de
  // hicbir yere gitmiyordu. Uyeden okuyamadigi bir metni kabul etmesi
  // isteniyordu.
  testWidgets('yasal metin baglantilari bir yere gidiyor', (tester) async {
    final acildi = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onCheckEmailStatus: (_) async => true,
          onSignIn: (_, _) async {},
          onTermsOfService: () => acildi.add('terms'),
          onPrivacyPolicy: () => acildi.add('privacy'),
        ),
      ),
    );

    final kosullar = find.text('Kullanım Koşulları');
    await tester.ensureVisible(kosullar);
    await tester.pumpAndSettle();
    await tester.tap(kosullar);
    await tester.pumpAndSettle();

    final gizlilik = find.text('Gizlilik Politikası');
    await tester.ensureVisible(gizlilik);
    await tester.pumpAndSettle();
    await tester.tap(gizlilik);
    await tester.pumpAndSettle();

    expect(acildi, ['terms', 'privacy']);
  });
}
