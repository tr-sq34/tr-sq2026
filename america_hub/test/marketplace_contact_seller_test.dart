import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:america_hub/features/messaging/presentation/screens/conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_messaging.dart';

const _listing = MarketplaceListing(
  id: 'listing-detail',
  title: 'Test ilanı',
  category: 'Ev',
  price: 42,
  condition: 'Yeni',
  location: 'New York, NY',
  sellerName: 'Can B.',
  sellerId: 'satici-can',
  imageUrl: '',
);

Future<void> pumpDetail(
  WidgetTester tester, {
  required RecordingDirectMessages directMessages,
  String viewerId = 'me',
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MarketplaceDetailScreen(
        listing: _listing,
        controller: MarketplaceController(
          repository: MockMarketplaceRepository(),
        ),
        messaging: testMessaging(
          directMessages: directMessages,
          viewerId: viewerId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // "Satıcı ile İletişime Geç" aylardır hiçbir şey göndermeden "Mesaj İsteği
  // Gönderildi" diyordu.
  testWidgets('iletisime gec dugmesi saticiyla sohbeti aciyor', (tester) async {
    final directMessages = RecordingDirectMessages();
    await pumpDetail(tester, directMessages: directMessages);

    await tester.tap(find.text('Satıcı ile İletişime Geç'));
    await tester.pumpAndSettle();

    expect(directMessages.opened, ['satici-can']);
    expect(find.byType(ConversationScreen), findsOneWidget);
    // Alıcı ne söyleyeceğini kendi yazıyor: kimse adına mesaj gönderilmiyor.
    expect(directMessages.sent, isEmpty);
  });

  testWidgets('hazir soru ekranda yazdigi gibi gidiyor', (tester) async {
    final directMessages = RecordingDirectMessages();
    await pumpDetail(tester, directMessages: directMessages);

    await tester.tap(find.text('Hâlâ satılık mı?'));
    await tester.pumpAndSettle();

    expect(directMessages.opened, ['satici-can']);
    expect(directMessages.sent, ['Hâlâ satılık mı?']);
    expect(find.byType(ConversationScreen), findsOneWidget);
  });

  testWidgets('sunucu yanit vermezse gonderildi denmiyor', (tester) async {
    final directMessages = RecordingDirectMessages(fails: true);
    await pumpDetail(tester, directMessages: directMessages);

    await tester.tap(find.text('Satıcı ile İletişime Geç'));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen), findsNothing);
    expect(find.text('Satıcıyla sohbet şu anda açılamadı.'), findsOneWidget);
    expect(find.text('Mesaj İsteği Gönderildi'), findsNothing);
  });

  // Kendi ilanında satıcı sensin; kendine mesaj gönderilmiyor.
  testWidgets('kendi ilaninda satici dugmesi hic yok', (tester) async {
    final directMessages = RecordingDirectMessages();
    await pumpDetail(
      tester,
      directMessages: directMessages,
      viewerId: 'satici-can',
    );

    expect(find.text('Satıcı ile İletişime Geç'), findsNothing);
    expect(find.text('Hâlâ satılık mı?'), findsNothing);
  });
}
