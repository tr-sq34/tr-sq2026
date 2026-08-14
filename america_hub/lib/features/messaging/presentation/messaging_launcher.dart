import 'package:flutter/material.dart';

import '../../../core/utils/uuid.dart';
import '../application/direct_conversation_controller.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/direct_message_repository.dart';
import '../domain/repositories/message_moderation_repository.dart';
import 'screens/conversation_screen.dart';

/// Bir üyeyle sohbeti nereden olursa olsun açar.
///
/// Çarşı'daki "Satıcı ile İletişime Geç" düğmesi aylardır hiçbir şey
/// göndermeden "Mesaj İsteği Gönderildi" diyordu. Sohbeti açmak için gereken
/// üç parça (depo, denetleyici üreticisi, moderasyon) mesajlaşma özelliğinin
/// içinde duruyor; Çarşı'ya üçünü birden taşımak yerine, açma işi tek bir
/// nesnede toplanıp oraya o veriliyor.
class MessagingLauncher {
  const MessagingLauncher({
    required this.directMessages,
    required this.createController,
    required this.moderationRepository,
    required this.viewerId,
  });

  final DirectMessageRepository directMessages;
  final DirectConversationControllerFactory createController;
  final MessageModerationRepository moderationRepository;

  /// Oturumdaki üye. Kurulurken değil, sorulduğunda okunuyor: kabuk giriş
  /// yapılmadan da kuruluyor.
  final String? Function() viewerId;

  /// Kendine mesaj gönderilemez; kimliği bilinmeyen bir satıcıya da.
  bool canMessage(String userId) =>
      userId.isNotEmpty && userId != (viewerId() ?? '');

  /// Sohbeti sunucuda açar ve ekranı gösterir.
  ///
  /// Sunucu yanıt vermezse `false` dönüyor: çağıran taraf ne olduğunu söylesin
  /// diye. Sessizce hiçbir şey yapmak, olmayan bir mesajı "gönderildi" saymanın
  /// başka bir biçimi olurdu.
  ///
  /// [firstMessage] verilirse sohbet açılır açılmaz o mesaj gönderiliyor:
  /// ilandaki "Hâlâ satılık mı?" kısayolu tam olarak yazdığı şeyi göndersin
  /// diye.
  Future<bool> openWithMember(
    BuildContext context, {
    required String userId,
    String? firstMessage,
  }) async {
    final Conversation conversation;
    try {
      conversation = await directMessages.openDirectConversation(userId);
      if (firstMessage != null && firstMessage.trim().isNotEmpty) {
        await directMessages.sendMessage(
          conversationId: conversation.id,
          body: firstMessage.trim(),
          // Mesajın kimliği aynı zamanda tekrar anahtarı: yeniden denemek
          // ikinci bir mesaj bırakmıyor.
          idempotencyKey: generateUuidV4(),
        );
      }
    } catch (_) {
      return false;
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          conversation: conversation,
          createController: createController,
          moderationRepository: moderationRepository,
        ),
      ),
    );
    return true;
  }
}
