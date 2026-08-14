import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/events/application/events_controller.dart';
import 'package:america_hub/features/events/domain/entities/community_event.dart';
import 'package:america_hub/features/events/domain/repositories/events_repository.dart';
import 'package:america_hub/features/events/presentation/screens/events_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CommunityEvent buildEvent({
  EventStatus status = EventStatus.published,
  String? cancellationReason,
  int? capacity,
  String? externalUrl,
  int attendeeCount = 12,
  int interestedCount = 0,
}) => CommunityEvent(
  id: 'event-1',
  title: 'Simit ve Sohbet',
  category: 'Buluşma',
  startsAt: DateTime(2026, 9, 5, 10),
  location: 'Astoria Park',
  city: 'Queens, NY',
  attendeeCount: attendeeCount,
  priceLabel: 'Ücretsiz',
  imageUrl: '',
  description: 'Kahvaltı ve sohbet.',
  status: status,
  cancellationReason: cancellationReason,
  capacity: capacity,
  externalUrl: externalUrl,
  interestedCount: interestedCount,
);

/// Katilim isteginin sonucunu testin belirlemesi icin: sunucu kontenjan
/// dolu oldugunda 409 donuyor, depo da onu firlatiyor.
class _StubEventsRepository implements EventsRepository {
  _StubEventsRepository(this.event, {this.failRsvp = false});
  final CommunityEvent event;
  final bool failRsvp;

  @override
  Future<CursorPage<CommunityEvent>> fetchPage({String? cursor, int limit = 20}) async =>
      CursorPage(items: [event], nextCursor: null);

  @override
  Future<List<CommunityEvent>> getUpcomingEvents() async => [event];

  @override
  Future<CommunityEvent> updateRsvp({required String eventId, required EventRsvpStatus status}) async {
    if (failRsvp) throw Exception('EVENT_FULL');
    return event.copyWith(rsvpStatus: status);
  }
}

Future<EventsController> pumpDetail(
  WidgetTester tester,
  CommunityEvent event, {
  bool failRsvp = false,
}) async {
  final controller = EventsController(
    repository: _StubEventsRepository(event, failRsvp: failRsvp),
  );
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(home: EventDetailScreen(event: event, controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // Panelden iptal edilen etkinlik uygulamada hicbir sey degistirmiyordu:
  // ekran normal gorunuyor, "Katilacagim" dugmesi acik duruyordu.
  testWidgets('iptal edilen etkinlik gerekcesiyle gorunuyor', (tester) async {
    await pumpDetail(
      tester,
      buildEvent(
        status: EventStatus.cancelled,
        cancellationReason: 'Mekan son anda kapandı.',
      ),
    );

    expect(find.text('Bu etkinlik iptal edildi'), findsOneWidget);
    expect(find.text('Mekan son anda kapandı.'), findsOneWidget);
    expect(find.text('Katilacagim'), findsNothing);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  // Kontenjan sunucuda ilk gunden beri uygulaniyordu, uygulama hic okumuyordu.
  testWidgets('kalan kontenjan yaziyor', (tester) async {
    await pumpDetail(tester, buildEvent(capacity: 20, attendeeCount: 12));

    expect(find.text('8 kisilik yer kaldi'), findsOneWidget);
  });

  testWidgets('kontenjan dolunca katilim dugmesi kapali', (tester) async {
    await pumpDetail(tester, buildEvent(capacity: 12, attendeeCount: 12));

    expect(find.text('Kontenjan doldu'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('kontenjani olmayan etkinlikte kontenjan satiri yok', (
    tester,
  ) async {
    await pumpDetail(tester, buildEvent());

    expect(find.textContaining('yer kaldi'), findsNothing);
    expect(find.text('Katilacagim'), findsOneWidget);
  });

  // Katilim reddedilirse eskiden hicbir sey gorunmuyordu: yazi eski haline
  // donuyor ve neden olmadigi hic soylenmiyordu.
  testWidgets('katilim kaydedilemezse kullaniciya soyleniyor', (tester) async {
    await pumpDetail(tester, buildEvent(), failRsvp: true);

    await tester.tap(find.text('Katilacagim'));
    await tester.pumpAndSettle();

    expect(find.text('Katılım kaydedilemedi, tekrar dene.'), findsOneWidget);
  });

  testWidgets('bilet baglantisi olan etkinlikte dugme cikiyor', (tester) async {
    await pumpDetail(
      tester,
      buildEvent(externalUrl: 'https://etkinlik.example/bilet'),
    );

    expect(find.text('Bilet ve kayit sayfasi'), findsOneWidget);
  });

  testWidgets('baglantisi olmayan etkinlikte uydurma vaat yok', (tester) async {
    await pumpDetail(tester, buildEvent());

    expect(find.text('Bilet ve kayit sayfasi'), findsNothing);
    // Uc satirlik sabit "avantaj" listesi kaldirildi: ucu de her etkinlikte
    // ayni yaziyordu ve hicbirinin karsiligi yoktu.
    expect(find.text('Mobil etkinlik bileti'), findsNothing);
    expect(find.text('Tum ucretler dahil'), findsNothing);
    expect(find.textContaining('bildirim gondeririz'), findsNothing);
  });
}
