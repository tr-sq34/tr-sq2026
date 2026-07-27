import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.text('Çarşı'), findsOneWidget);
    expect(find.text('El yapımı çay seti'), findsOneWidget);
  });
}

class MarketplaceTestHost extends StatelessWidget {
  const MarketplaceTestHost({super.key});

  @override
  Widget build(BuildContext context) => MarketplaceScreen(controller: MarketplaceController(repository: MockMarketplaceRepository()));
}
