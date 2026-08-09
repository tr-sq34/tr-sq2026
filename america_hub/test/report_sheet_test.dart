import 'package:america_hub/features/messaging/data/repositories/mock_message_moderation_repository.dart';
import 'package:america_hub/features/messaging/domain/entities/message_report.dart';
import 'package:america_hub/features/messaging/presentation/widgets/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a report is only sent once a category is picked', (tester) async {
    final repository = MockMessageModerationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReportSheet(
              context,
              repository: repository,
              conversationId: 'dm-1',
              messageEventId: r'$event-1',
              subjectLabel: 'Elif Demir',
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    // Nothing chosen yet, so the submit button must not be able to file a
    // report with no category — an uncategorised one cannot be triaged.
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    // Ten categories do not fit the sheet, so the one under test has to be
    // scrolled to first.
    await tester.scrollUntilVisible(
      find.text(ReportCategory.harassment.label),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(ReportCategory.harassment.label));
    await tester.pump();
    await tester.tap(find.text('Şikâyeti gönder'));
    await tester.pumpAndSettle();

    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.category, ReportCategory.harassment);
    expect(repository.reports.single.messageEventId, r'$event-1');
  });
}
