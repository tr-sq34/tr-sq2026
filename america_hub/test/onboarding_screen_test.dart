import 'package:america_hub/features/auth/data/datasources/device_location_source.dart';
import 'package:america_hub/features/auth/data/datasources/us_places_local_datasource.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:america_hub/features/auth/presentation/widgets/onboarding/arrival_step.dart';
import 'package:america_hub/features/auth/presentation/widgets/onboarding/persona_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeLocationSource implements DeviceLocationSource {
  _FakeLocationSource(this.result);

  final DeviceLocationResult result;
  int calls = 0;

  @override
  Future<DeviceLocationResult> resolve() async {
    calls++;
    return result;
  }
}

const _denied = DeviceLocationResult(DeviceLocationStatus.permissionDenied);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final drafts = <OnboardingDraft>[];
  final places = UsPlacesLocalDataSource();

  setUpAll(() async {
    // Inter is fetched over the network at runtime, which a test has no
    // business doing; without this the loader would try and log a failure.
    GoogleFonts.config.allowRuntimeFetching = false;
    // rootBundle only reads outside the fake clock, so the index is loaded
    // here rather than on the first keystroke inside a test.
    await places.ensureLoaded();
  });
  setUp(drafts.clear);

  Future<void> pumpScreen(
    WidgetTester tester, {
    DeviceLocationResult location = _denied,
  }) async {
    // A phone-sized surface: the 800x600 default clips the persona grid, and a
    // card that is off screen cannot be tapped.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // The backdrop drifts forever unless reduce-motion is on, and a
          // never-ending animation means pumpAndSettle never returns.
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: OnboardingScreen(
              places: places,
              locationSource: _FakeLocationSource(location),
              now: DateTime(2026, 8, 10),
              // enterText delivers onChanged outside the fake clock, so a
              // debounce timer created there would never fire under pump().
              searchDebounce: Duration.zero,
              onComplete: (draft) async => drafts.add(draft),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types into the search box and waits out the asynchronous lookup.
  Future<void> searchCity(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pumpAndSettle();
  }

  /// Waits out the 450 ms auto-advance delay and the page transition.
  Future<void> settleAdvance(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// Scrolls the persona list until the card is built, then taps it. The list
  /// is lazy, so a card further down does not exist until it is scrolled to.
  Future<void> pickPersona(WidgetTester tester, String label) async {
    final target = find.text(label);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        260,
        scrollable: find
            .descendant(
              of: find.byType(PersonaStep),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The year strip scrolls sideways from the current year backwards.
  Future<void> pickYear(WidgetTester tester, String year) async {
    // The strip sits below the month grid, so it is not even built until the
    // page is scrolled down to it — and a widget off screen cannot be dragged.
    final heading = find.text('HANGİ YIL?');
    if (heading.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        heading,
        220,
        scrollable: find
            .descendant(
              of: find.byType(ArrivalStep),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(heading);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text(year),
      find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is ListView && widget.scrollDirection == Axis.horizontal,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(year));
  }

  testWidgets('picking a city from the list moves on by itself', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Amerika’da doğdum'), findsNothing);

    await searchCity(tester, 'jers');
    expect(find.text('Jersey City, NJ'), findsOneWidget);

    await tester.tap(find.text('Jersey City, NJ'));
    await settleAdvance(tester);

    expect(find.text('Amerika’da doğdum'), findsOneWidget);
  });

  testWidgets('being born here answers the arrival step and moves on', (
    tester,
  ) async {
    await pumpScreen(tester);
    await searchCity(tester, 'jers');
    await tester.tap(find.text('Jersey City, NJ'));
    await settleAdvance(tester);

    await tester.tap(find.byType(Switch));
    await settleAdvance(tester);

    // The month grid is gone and the persona step is up.
    expect(find.text('Ocak'), findsNothing);
    expect(find.text('İşletmemi tanıtıyorum'), findsOneWidget);
  });

  testWidgets('the final call to action stays dead until a persona is picked', (
    tester,
  ) async {
    await pumpScreen(tester);
    await searchCity(tester, 'jers');
    await tester.tap(find.text('Jersey City, NJ'));
    await settleAdvance(tester);
    await tester.tap(find.byType(Switch));
    await settleAdvance(tester);

    ElevatedButton cta() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'TurkSquare’e gir'),
    );

    expect(cta().onPressed, isNull);

    await pickPersona(tester, 'İşletmemi tanıtıyorum');

    expect(cta().onPressed, isNotNull);
  });

  testWidgets('the first persona picked becomes the primary intent', (
    tester,
  ) async {
    await pumpScreen(tester);
    await searchCity(tester, 'jers');
    await tester.tap(find.text('Jersey City, NJ'));
    await settleAdvance(tester);

    // March 2019.
    await tester.tap(find.text('Mart'));
    await tester.pumpAndSettle();
    await pickYear(tester, '2019');
    await settleAdvance(tester);

    await pickPersona(tester, 'İş arıyorum');
    await pickPersona(tester, 'Öğrenciyim');
    await tester.tap(find.text('TurkSquare’e gir'));
    await tester.pumpAndSettle();

    expect(drafts, hasLength(1));
    final draft = drafts.single;
    expect(draft.city, 'Jersey City');
    expect(draft.regionCode, 'NJ');
    expect(draft.countryCode, 'US');
    expect(draft.bornInUs, isFalse);
    expect(draft.arrivedMonth, 3);
    expect(draft.arrivedYear, 2019);
    expect(draft.interests, ['job_seeking', 'student']);
    expect(draft.primaryIntent, 'job_seeking');
  });

  testWidgets('someone outside the US never sees the arrival question', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Şu an ABD dışındayım'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'İstanbul');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    expect(find.text('Amerika’da doğdum'), findsNothing);
    expect(find.text('İşletmemi tanıtıyorum'), findsOneWidget);

    await pickPersona(tester, 'Türk topluluğuyla tanışmak');
    await tester.tap(find.text('TurkSquare’e gir'));
    await tester.pumpAndSettle();

    final draft = drafts.single;
    expect(draft.city, 'İstanbul');
    expect(draft.countryCode, 'TR');
    // Nothing downstream can rank an address outside the states, so no state
    // code is invented for it.
    expect(draft.regionCode, isNull);
    expect(draft.arrivedMonth, isNull);
  });

  testWidgets('a resolved device location advances without any typing', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      location: const DeviceLocationResult(
        DeviceLocationStatus.resolved,
        city: 'Paterson',
        stateCode: 'NJ',
        countryCode: 'US',
      ),
    );

    await tester.tap(find.text('Konumumu kullan'));
    await tester.pumpAndSettle();
    await settleAdvance(tester);

    expect(find.text('Amerika’da doğdum'), findsOneWidget);
  });

  testWidgets('a denied permission explains itself instead of faking a city', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Konumumu kullan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Konum izni verilmedi. Şehrini aşağıdan aratabilirsin.'),
      findsOneWidget,
    );
    // The step is not blocked by the refusal — searching still works.
    expect(tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Devam'),
    ).onPressed, isNull);

    await searchCity(tester, 'jers');
    expect(find.text('Jersey City, NJ'), findsOneWidget);
  });
}
