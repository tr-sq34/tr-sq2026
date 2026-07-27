import 'package:america_hub/features/home/presentation/screens/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'canlı ihale kartı küçük mobil görünümde taşmadan render edilir',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 194,
                child: LiveBiddingCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('CANLI İHALE'), findsWidgets);
      // Widget tests intentionally block remote image downloads; consume that
      // expected image-loading failure before checking layout exceptions.
      expect(tester.takeException(), isA<NetworkImageLoadException>());
      expect(tester.takeException(), isNull);
    },
  );
}
