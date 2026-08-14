import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/events/application/events_controller.dart';
import 'package:america_hub/features/events/domain/entities/community_event.dart';
import 'package:america_hub/features/events/domain/repositories/events_repository.dart';
import 'package:america_hub/features/events/presentation/screens/events_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CommunityEvent event({
  required String id,
  required String title,
  required String category,
  required String city,
  required DateTime startsAt,
}) => CommunityEvent(
  id: id,
  title: title,
  category: category,
  startsAt: startsAt,
  location: 'Salon',
  city: city,
  attendeeCount: 5,
  priceLabel: 'Ücretsiz',
  imageUrl: '',
);

final _events = [
  event(id: 'e1', title: 'Simit ve Sohbet', category: 'Community', city: 'Queens, NY', startsAt: DateTime(2026, 8, 20, 10)),
  event(id: 'e2', title: 'Caz Gecesi', category: 'Music', city: 'Chicago, IL', startsAt: DateTime(2026, 9, 12, 20)),
];

class _StubEventsRepository implements EventsRepository {
  @override
  Future<CursorPage<CommunityEvent>> fetchPage({String? cursor, int limit = 20}) async =>
      CursorPage(items: _events, nextCursor: null);

  @override
  Future<List<CommunityEvent>> getUpcomingEvents() async => _events;

  @override
  Future<CommunityEvent> updateRsvp({required String eventId, required EventRsvpStatus status}) async =>
      _events.first;
}

Future<EventsController> pumpEvents(WidgetTester tester) async {
  final controller = EventsController(
    repository: _StubEventsRepository(),
    now: () => DateTime(2026, 8, 14, 9),
  );
  await controller.load();
  await tester.pumpWidget(MaterialApp(home: EventsScreen(controller: controller)));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // Basliktaki kutu bir arama alani gibi duruyor ama icine yazi bile
  // girilemiyordu; sunucuda etkinlik aramasi diye bir sey yok.
  testWidgets('calismayan arama kutusu kalmadi', (tester) async {
    await pumpEvents(tester);

    expect(find.text('Etkinlik, grup veya mekan ara'), findsNothing);
  });

  // Iki cip de ok isaretiyle suzgec gibi duruyor ama hicbir seye bagli
  // degildi: sehir koda yazilmisti, tarih ise gercek secimi yansitmiyordu.
  testWidgets('sehir cipi gercek sehir suzgecini aciyor', (tester) async {
    final controller = await pumpEvents(tester);
    expect(find.text('Tüm şehirler'), findsOneWidget);

    await tester.tap(find.text('Tüm şehirler'));
    await tester.pumpAndSettle();
    expect(find.text('Şehir seç'), findsOneWidget);

    await tester.tap(find.text('Chicago, IL').last);
    await tester.pumpAndSettle();

    expect(controller.city, 'Chicago, IL');
    expect(find.text('Chicago, IL'), findsWidgets);
    expect(find.text('Simit ve Sohbet'), findsNothing);
  });

  testWidgets('tarih cipi o an secili suzgeci yaziyor', (tester) async {
    final controller = await pumpEvents(tester);
    expect(find.text('Tüm tarihler'), findsOneWidget);

    await tester.tap(find.text('Tüm tarihler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu ay').last);
    await tester.pumpAndSettle();

    expect(controller.dateFilter, EventDateFilter.thisMonth);
    expect(find.text('Bu ay'), findsOneWidget);
  });

  // Suzgecteki ucuncu secenek tam olarak agustos ayini suzuyordu: yazildigi
  // ay. Aralikta acan birine "Agustos" gosterip her seferinde bos liste
  // veriyordu.
  test('bu ay suzgeci bulunulan aya bakiyor', () async {
    final aralik = EventsController(
      repository: _StubEventsRepository(),
      now: () => DateTime(2026, 12, 3),
    );
    await aralik.load();
    aralik.updateFilters(dateFilter: EventDateFilter.thisMonth);
    expect(aralik.visibleItems, isEmpty);

    final eylul = EventsController(
      repository: _StubEventsRepository(),
      now: () => DateTime(2026, 9, 1),
    );
    await eylul.load();
    eylul.updateFilters(dateFilter: EventDateFilter.thisMonth);
    expect(eylul.visibleItems.single.id, 'e2');
  });

  // Dokuz kategori koda yazilmisti ve her biri Unsplash'ten bir fotograf
  // cekiyordu. Karsiligi olmayanlar dokununca hep bos ekran aciyordu.
  testWidgets('kategori kutulari yalnizca gercek kategorilerden cikiyor', (
    tester,
  ) async {
    await pumpEvents(tester);

    expect(find.text('Topluluk'), findsOneWidget);
    expect(find.text('Konserler'), findsOneWidget);
    // Elde bu kategorilerde etkinlik yok.
    expect(find.text('Sinema'), findsNothing);
    expect(find.text('Sergiler'), findsNothing);
    expect(find.text('Atölyeler'), findsNothing);
  });
}
