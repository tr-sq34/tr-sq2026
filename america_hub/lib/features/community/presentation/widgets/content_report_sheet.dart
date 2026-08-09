import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/repositories/content_moderation_repository.dart';

/// Opens the report flow for a post, comment or story and returns true when a
/// report was filed.
///
/// A sheet rather than a screen, for the same reason messaging uses one:
/// reporting has to be one tap from the content itself, and a route push would
/// take the user away from the thing they are trying to describe.
Future<bool> showContentReportSheet(
  BuildContext context, {
  required ContentModerationRepository repository,
  required ContentReportTarget targetType,
  required String targetId,
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
    builder: (_) => _ContentReportSheet(
      repository: repository,
      targetType: targetType,
      targetId: targetId,
      subjectLabel: subjectLabel,
    ),
  );
  return filed ?? false;
}

class _ContentReportSheet extends StatefulWidget {
  const _ContentReportSheet({
    required this.repository,
    required this.targetType,
    required this.targetId,
    required this.subjectLabel,
  });

  final ContentModerationRepository repository;
  final ContentReportTarget targetType;
  final String targetId;
  final String subjectLabel;

  @override
  State<_ContentReportSheet> createState() => _ContentReportSheetState();
}

class _ContentReportSheetState extends State<_ContentReportSheet> {
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
      final receipt = await widget.repository.reportContent(
        targetType: widget.targetType,
        targetId: widget.targetId,
        category: category,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      // A duplicate is not a failure: the report the user wanted already
      // exists. Telling them so is more honest than a second confirmation that
      // implies a second review.
      // Hide first: a snackbar still on screen from an earlier report would
      // queue this one behind it, so the user would read the outcome of the
      // previous report as the answer to this one.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              receipt.duplicate
                  ? 'Bu içerik için şikâyetin zaten inceleniyor.'
                  : 'Şikâyetin alındı. En geç 24 saat içinde incelenecek.',
            ),
          ),
        );
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    '${widget.targetType.label} şikâyet et',
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
                    // 500, not the 1000 messaging allows: the community service
                    // rejects anything longer, and a silent truncation on the
                    // way out would drop the part the user cared about.
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText:
                          'Eklemek istediğin bir şey var mı? (isteğe bağlı)',
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
                : (isDarkMode
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC)),
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
