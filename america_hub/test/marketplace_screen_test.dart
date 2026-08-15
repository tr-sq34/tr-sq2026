import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/domain/entities/marketplace_listing.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_member_capabilities.dart';
import 'support/test_messaging.dart';

void main() {
  testWidgets('Çarşı renders after initial load without viewport exceptions', (tester) async {
    final controller = MarketplaceController(repository: MockMarketplaceRepository());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430, maxHeight: 900),
            child: const SizedBox.expand(child: Scaffold(body: MarketplaceTestHost())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Başlığı kabuk yazıyor. Ekran bir kez daha yazınca üstte iki "Çarşı"
    // görünüyordu; o yüzden buradaki tek doğru sayı sıfır.
    expect(find.text('Çarşı'), findsNothing);
    // The card prints the price and the title in one line ("$32 · …"), so the
    // title is matched as a substring rather than as a whole label.
    expect(find.textContaining('El yapımı çay seti'), findsOneWidget);
  });

  // İstek başarısız olduğunda da "İlan bulunamadı · Yeni ilanlar eklendiğinde
  // burada görünecek" yazıyordu: sunucu cevap vermediği hâlde üyeye Çarşı'nın
  // boş olduğu söyleniyordu.
  testWidgets('istek başarısızsa Çarşı boş değil, ulaşılamadı diyor', (tester) async {
    final controller = MarketplaceController(
      repository: _FailingMarketplaceRepository(),
    );
    await controller.loadInitial();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430, maxHeight: 900),
            child: SizedBox.expand(
              child: Scaffold(
                body: MarketplaceFeedView(
                  controller: controller,
                  local: false,
                  messaging: testMessaging(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('İlan bulunamadı'), findsNothing);
    expect(find.text('Yüklenemedi'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
  });
}

class _FailingMarketplaceRepository extends MockMarketplaceRepository {
  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({String? cursor, int limit = 20}) async =>
      throw const ApiException(message: 'Sunucuya ulaşılamadı.', statusCode: 503);
}

class MarketplaceTestHost extends StatelessWidget {
  const MarketplaceTestHost({super.key});

  @override
  Widget build(BuildContext context) => MarketplaceScreen(
        controller: MarketplaceController(repository: MockMarketplaceRepository()),
        memberCapabilitiesController: testMemberCapabilitiesController(),
        messaging: testMessaging(),
      );
}
