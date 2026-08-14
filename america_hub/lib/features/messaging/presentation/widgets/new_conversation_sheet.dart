import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../../profile/application/friendship_controller.dart';
import '../../../profile/domain/entities/friendship.dart';

/// Yeni sohbet: kiminle?
///
/// Bu düğme uzun süre "yakında" diyordu. Söyleyecek bir şeyi yoktu, çünkü
/// arkadaşlık diye bir şey yoktu - liste her üye için boştu. Şimdi var.
///
/// Listede yalnızca arkadaşlar duruyor. Mesajlaşma karşılıklı rızaya bağlı ve
/// arkadaşlık o rızanın kendisi; buradan bir üye arama kutusu açmak, o kararı
/// atlamak olurdu.
class NewConversationSheet extends StatefulWidget {
  const NewConversationSheet({super.key, required this.controller});

  final FriendshipController controller;

  @override
  State<NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<NewConversationSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.controller.hasLoaded) widget.controller.load();
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .6,
    minChildSize: .35,
    maxChildSize: .92,
    expand: false,
    builder: (context, scrollController) => Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.profileBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Yeni sohbet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Yalnızca arkadaşlarınla mesajlaşabilirsin.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(scrollController)),
          ],
        ),
      ),
    ),
  );

  Widget _body(ScrollController scrollController) {
    final controller = widget.controller;
    if (controller.isLoading && !controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null && !controller.hasLoaded) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.load,
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    }
    if (controller.friends.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Henüz arkadaşın yok. Akıştaki bir paylaşımın menüsünden '
            '"Arkadaş ekle" diyerek başlayabilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: controller.friends.length,
      itemBuilder: (context, index) {
        final friend = controller.friends[index];
        final avatar = appImageProvider(friend.avatarUrl);
        final place = friend.placeLabel;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.profileTint,
            backgroundImage: avatar,
            child: avatar == null
                ? const Icon(Icons.person_outline, size: 20)
                : null,
          ),
          title: Text(
            friend.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: place.isEmpty ? null : Text(place),
          onTap: () => Navigator.of(context).pop<FriendSummary>(friend),
        );
      },
    );
  }
}
