import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/datasources/device_location_source.dart';
import 'package:america_hub/features/auth/data/datasources/us_places_local_datasource.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_profile.dart';
import 'package:america_hub/features/profile/presentation/screens/location_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _SilentLocationSource implements DeviceLocationSource {
  const _SilentLocationSource();

  @override
  Future<DeviceLocationResult> resolve() async =>
      const DeviceLocationResult(DeviceLocationStatus.permissionDenied);
}

/// Kayıtlı tercihleri tutan bir kimlik deposu: ekranın derdi konumu
/// değiştirmek, ama sunucu bütün cevapları birlikte istiyor.
class _FakeAuth extends MockAuthRepository {
  _FakeAuth({this.stored, this.readFails = false});

  OnboardingProfile? stored;
  bool readFails;
  final List<OnboardingDraft> saved = [];

  @override
  Future<OnboardingProfile> getOnboarding() async {
    if (readFails) throw StateError('down');
    return stored ?? const OnboardingProfile(completed: false);
  }

  @override
  Future<void> saveOnboarding(OnboardingDraft draft) async => saved.add(draft);
}

const _stored = OnboardingProfile(
  completed: true,
  city: 'Paterson',
  countryCode: 'US',
  regionCode: 'NJ',
  interests: ['newcomer', 'community'],
  primaryIntent: 'community',
  bornInUs: false,
  arrivedMonth: 4,
  arrivedYear: 2021,
  originCountry: 'TR',
  originCity: 'İzmir',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final places = UsPlacesLocalDataSource();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await places.ensureLoaded();
  });

  Future<({_FakeAuth auth, List<String> reloads})> pumpScreen(
    WidgetTester tester,
    _FakeAuth auth,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final reloads = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Arka plandaki ışık sonsuza kadar süzülüyor; pumpAndSettle asla
          // dönmesin diye değil, dönebilsin diye kapatılıyor.
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: LocationEditScreen(
              authController: AuthController(
                repository: auth,
                sessionStore: InMemorySessionStore(),
                tokenStore: InMemoryTokenStore(),
              ),
              places: places,
              locationSource: const _SilentLocationSource(),
              searchDebounce: Duration.zero,
              onSaved: () async => reloads.add('reload'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (auth: auth, reloads: reloads);
  }

  testWidgets('kayitli sehir formda hazir duruyor', (tester) async {
    await pumpScreen(tester, _FakeAuth(stored: _stored));

    expect(find.text('Paterson, NJ'), findsOneWidget);
  });

  testWidgets('yeni sehir kaydedilirken diger tercihler aynen geri gidiyor', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, _FakeAuth(stored: _stored));

    await tester.enterText(find.byType(TextField).first, 'Cliffside Park');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliffside Park, NJ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(harness.auth.saved, hasLength(1));
    final draft = harness.auth.saved.single;
    expect(draft.city, 'Cliffside Park');
    expect(draft.regionCode, 'NJ');
    // Konumu değiştirmek ilgi alanlarını sıfırlamıyor: sunucu ikisini bir
    // arada istiyor, ekran da okuduğunu olduğu gibi geri veriyor.
    expect(draft.interests, ['newcomer', 'community']);
    expect(draft.primaryIntent, 'community');
    expect(draft.arrivedYear, 2021);
    expect(draft.originCity, 'İzmir');
    expect(harness.reloads, ['reload']);
  });

  testWidgets('tercihler okunamadiysa form acilmiyor, nedeni yaziyor', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, _FakeAuth(readFails: true));

    expect(
      find.text('Kayıtlı tercihlerin okunamadı. Bağlantını kontrol et.'),
      findsOneWidget,
    );
    // Boş bir form gösterip kaydettirmek, okunamayan tercihlerin üzerine
    // yazmak olurdu.
    expect(find.text('Kaydet'), findsNothing);
    expect(harness.auth.saved, isEmpty);
  });
}
