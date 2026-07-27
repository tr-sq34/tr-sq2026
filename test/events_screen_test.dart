import 'package:america_hub/features/events/application/events_controller.dart';
import 'package:america_hub/features/events/data/repositories/mock_events_repository.dart';
import 'package:america_hub/features/events/presentation/screens/events_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('events screen renders after its initial load', (tester) async {
    final controller = EventsController(repository: MockEventsRepository());
    await controller.load();
    expect(controller.items, isNotEmpty);
    await tester.pumpWidget(MaterialApp(home: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430, maxHeight: 900), child: const SizedBox.expand(child: Scaffold(body: _EventsTestHost()))))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Turkish Summer Picnic'), findsOneWidget);
  });
}

class _EventsTestHost extends StatelessWidget {
  const _EventsTestHost();
  @override
  Widget build(BuildContext context) {
    final controller = EventsController(repository: MockEventsRepository());
    controller.load();
    return Stack(children: [SafeArea(child: Padding(padding: const EdgeInsets.only(bottom: 84), child: IndexedStack(index: 1, children: [const SizedBox(), EventsScreen(controller: controller)])))]);
  }
}
