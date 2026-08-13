import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../application/forum_controller.dart';
import '../../domain/entities/forum.dart';

/// Yeni konu açma kâğıdı. Ekran yerine kâğıt olmasının sebebi akıştaki
/// editörle aynı: yazmaya başlamak bir sayfa geçişi kadar uzak olmamalı.
Future<ForumTopic?> showTopicComposerSheet(
  BuildContext context, {
  required ForumController controller,
  required List<ForumCategory> categories,
  String? initialCategoryId,
}) => showModalBottomSheet<ForumTopic>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
  ),
  builder: (_) => _TopicComposerSheet(
    controller: controller,
    categories: categories,
    initialCategoryId: initialCategoryId,
  ),
);

class _TopicComposerSheet extends StatefulWidget {
  const _TopicComposerSheet({
    required this.controller,
    required this.categories,
    this.initialCategoryId,
  });

  final ForumController controller;
  final List<ForumCategory> categories;
  final String? initialCategoryId;

  @override
  State<_TopicComposerSheet> createState() => _TopicComposerSheetState();
}

class _TopicComposerSheetState extends State<_TopicComposerSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String _categoryId =
      widget.initialCategoryId ?? widget.categories.first.id;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  CreateTopicDraft get _draft => CreateTopicDraft(
    categoryId: _categoryId,
    title: _title.text,
    body: _body.text,
  );

  Future<void> _submit() async {
    // Doğrulama taslağın kendisinde: ekran da depo da aynı kuralı okuyor.
    final error = _draft.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final topic = await widget.controller.createTopic(_draft);
      if (mounted) Navigator.of(context).pop(topic);
    } on ApiException catch (exception) {
      setState(() {
        _sending = false;
        _error = exception.message;
      });
    } catch (_) {
      setState(() {
        _sending = false;
        _error = 'Konu açılamadı. Biraz sonra tekrar dener misin?';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Yeni konu',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sorunu arayan biri bulabilsin diye başlığı açık yaz.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final category in widget.categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${category.emoji} ${category.title}'),
                      selected: _categoryId == category.id,
                      onSelected: (_) =>
                          setState(() => _categoryId = category.id),
                      showCheckmark: false,
                      backgroundColor: AppColors.surface,
                      selectedColor: AppColors.primary.withValues(alpha: .12),
                      side: BorderSide(
                        color: _categoryId == category.id
                            ? AppColors.primary
                            : AppColors.surfaceBorder,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _categoryId == category.id
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            maxLength: CreateTopicDraft.maxTitleLength,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Başlık',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            maxLines: 6,
            maxLength: CreateTopicDraft.maxBodyLength,
            decoration: const InputDecoration(
              hintText: 'Durumunu anlat: ne denedin, nerede takıldın?',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.accentRose,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _sending ? 'Açılıyor…' : 'Konuyu aç',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
