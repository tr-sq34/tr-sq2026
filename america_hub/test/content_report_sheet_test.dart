import 'package:america_hub/features/community/data/repositories/mock_content_moderation_repository.dart';
import 'package:america_hub/features/community/domain/entities/content_report.dart';
import 'package:america_hub/features/community/presentation/widgets/content_report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(MockContentModerationRepository repository) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showContentReportSheet(
            context,
            repository: repository,
            targetType: ContentReportTarget.post,
            targetId: 'post-1',
            subjectLabel: 'Elif Demir',
          ),
          child: const Text('aç'),
        ),
      ),
    ),
  );

  Future<void> pickHarassment(WidgetTester tester) async {
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
  }

  testWidgets('a post report carries the target the user tapped', (
    tester,
  ) async {
    final repository = MockContentModerationRepository();
    await tester.pumpWidget(host(repository));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    // Nothing chosen yet, so the submit button must not be able to file a
    // report with no category — an uncategorised one cannot be triaged, and
    // guessing one would put the wrong deadline on it.
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await pickHarassment(tester);

    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.category, ReportCategory.harassment);
    expect(repository.reports.single.targetType, ContentReportTarget.post);
    expect(repository.reports.single.targetId, 'post-1');
    expect(
      find.text('Şikâyetin alındı. En geç 24 saat içinde incelenecek.'),
      findsOneWidget,
    );
  });

  testWidgets('reporting the same content twice is not an error', (
    tester,
  ) async {
    final repository = MockContentModerationRepository();
    await tester.pumpWidget(host(repository));

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await pickHarassment(tester);
    }

    // The second one closes the same way the first did. Showing a failure here
    // would push the user to keep trying to report something that is already
    // in the queue.
    expect(repository.reports, hasLength(2));
    expect(
      find.text('Bu içerik için şikâyetin zaten inceleniyor.'),
      findsOneWidget,
    );
  });
}
