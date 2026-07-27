import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_seller_profile_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('seller storefront renders without an exception', (tester) async {
    final controller = MarketplaceController(repository: MockMarketplaceRepository());
    await tester.pumpWidget(MaterialApp(home: MarketplaceSellerProfileScreen(controller: controller, sellerId: 'user-demo')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'Satıcı vitrini', caseSensitive: false)), findsOneWidget);
    expect(find.text('Ahmet Yılmaz'), findsOneWidget);
  });

  testWidgets('seller row opens storefront inside listing detail', (tester) async {
    final controller = MarketplaceController(repository: MockMarketplaceRepository());
    const listing = MarketplaceListing(id: 'listing-detail', title: 'Test ilanı', category: 'Ev', price: 42, condition: 'Yeni', location: 'New York, NY', sellerName: 'Can B.', imageUrl: '');

    await tester.pumpWidget(MaterialApp(home: MarketplaceDetailScreen(listing: listing, controller: controller)));
    final seller = find.text('Can B.');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(seller);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'Satıcı vitrini', caseSensitive: false)), findsOneWidget);
    expect(find.textContaining('ROZET'), findsOneWidget);
  });

  testWidgets('storefront opens from the Çarşı listing route', (tester) async {
    final controller = MarketplaceController(repository: MockMarketplaceRepository());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketplaceScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MarketplaceListingCard).first);
    await tester.pumpAndSettle();
    final seller = find.text('Zeynep A.');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(seller);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'Satıcı vitrini', caseSensitive: false)), findsOneWidget);
  });

  testWidgets('seller navigation stays stable inside an IndexedStack with mouse input', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MarketplaceController(repository: MockMarketplaceRepository());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: 1,
                children: [
                  const SizedBox.shrink(),
                  MarketplaceScreen(controller: controller),
                ],
              ),
              const Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: SizedBox(height: 64),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 300));
    await tester.tap(find.byType(MarketplaceListingCard).first);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(210, 500));
    final seller = find.text('Zeynep A.');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(seller);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(180, 360));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(RegExp(r'Satıcı vitrini', caseSensitive: false)), findsOneWidget);
    await mouse.removePointer();
  });
}
