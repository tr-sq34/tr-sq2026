import 'package:america_hub/features/messaging/domain/entities/conversation.dart';
import 'package:america_hub/features/messaging/presentation/screens/conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_messaging.dart';

final _conversation = Conversation(
  id: 'dm-satici-can',
  title: 'Can B.',
  preview: '',
  updatedAt: DateTime(2026, 8, 14),
  kind: ConversationKind.direct,
  participantId: 'satici-can',
);

Future<RecordingDirectMessages> pumpConversation(WidgetTester tester) async {
  final directMessages = RecordingDirectMessages();
  final messaging = testMessaging(directMessages: directMessages);
  await tester.pumpWidget(
    MaterialApp(
      home: ConversationScreen(
        conversation: _conversation,
        createController: messaging.createController,
        moderationRepository: messaging.moderationRepository,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return directMessages;
}

void main() {
  // Basliktaki arama ve goruntulu arama dugmeleri de yazidaki atac dugmesi de
  // dokunulabilir gorunup hicbir sey yapmiyordu. Ne uygulamada ne sunucuda
  // arama var; mesaj da bastan sona yalnizca yazi tasiyor.
  testWidgets('sohbette calismayan dugme kalmadi', (tester) async {
    await pumpConversation(tester);

    expect(find.byIcon(Icons.call_rounded), findsNothing);
    expect(find.byIcon(Icons.videocam_rounded), findsNothing);
    expect(find.byIcon(Icons.attach_file_rounded), findsNothing);
  });

  testWidgets('kalan dugmeler gercekten calisiyor', (tester) async {
    final directMessages = await pumpConversation(tester);

    // Sikayet ve engelleme menusu duruyor: magazalarin sarti.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Şikâyet et'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(directMessages.sent, ['Merhaba']);
  });
}
