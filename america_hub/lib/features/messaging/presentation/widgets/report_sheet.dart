import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/message_report.dart';
import '../../domain/repositories/message_moderation_repository.dart';

/// Opens the report flow and returns true when a report was filed.
///
/// A sheet rather than a screen: reporting has to be reachable in one tap from
/// the message itself, and pushing a route would take the user away from the
/// conversation they are trying to describe.
Future<bool> showReportSheet(
  BuildContext context, {
  required MessageModerationRepository repository,
  required String conversationId,
  String? messageEventId,
  required String subjectLabel,
}) async {
  final filed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ReportSheet(
      repository: repository,
      conversationId: conversationId,
      messageEventId: messageEventId,
      subjectLabel: subjectLabel,
    ),
  );
  return filed ?? false;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.repository,
    required this.conversationId,
    required this.messageEventId,
    required this.subjectLabel,
  });

  final MessageModerationRepository repository;
  final String conversationId;
  final String? messageEventId;
  final String subjectLabel;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportCategory? _category;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await widget.repository.reportConversation(
        conversationId: widget.conversationId,
        messageEventId: widget.messageEventId,
        category: category,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Şikâyet gönderilemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final muted = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Padding(
      // Keeps the note field above the keyboard once it opens.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        minChildSize: .5,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  Text(
                    widget.messageEventId == null
                        ? 'Sohbeti şikâyet et'
                        : 'Mesajı şikâyet et',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.subjectLabel} · Şikâyetin moderasyon ekibine gider ve en geç 24 saat içinde incelenir. Şikâyet ettiğin kişiye bilgi verilmez.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 16),
                  for (final category in ReportCategory.values)
                    _CategoryTile(
                      category: category,
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                      isDarkMode: isDarkMode,
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Eklemek istediğin bir şey var mı? (isteğe bağlı)',
                      labelStyle: TextStyle(fontSize: 13, color: muted),
                      filled: true,
                      fillColor: isDarkMode
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // Disabled until a category is chosen: an uncategorised
                    // report cannot be triaged, and guessing one on the user's
                    // behalf would put the wrong deadline on it.
                    onPressed: _category == null || _sending ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Şikâyeti gönder'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.isDarkMode,
  });

  final ReportCategory category;
  final bool selected;
  final VoidCallback onTap;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: .10)
                : (isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.primary : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
