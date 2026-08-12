import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../promotions/application/promotions_controller.dart';
import '../../../promotions/domain/entities/promotion.dart';
import '../../../promotions/domain/repositories/promotion_repository.dart';
import '../../application/media_upload_controller.dart';
import '../../application/story_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../domain/entities/post_media_upload.dart';

/// Bir tanıtım talebinin kapsayabileceği en uzun aralık; sunucudaki
/// `MAX_PROMOTION_DAYS` ile aynı sayı. Burada da sınırlanıyor ki üye, tarihi
/// seçtiği anda reddedileceğini öğrensin.
const _maxPromotionDays = 30;

/// "12.08" — seçilen aralık düğmenin üstünde bu biçimde okunuyor, tanıtım
/// listesindeki `Promotion.windowLabel` ile aynı dilde.
String _formatDay(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}';

class StoryComposerSheet extends StatefulWidget {
  const StoryComposerSheet({
    super.key,
    required this.storyController,
    required this.mediaUploadController,
    required this.promotionsController,
  });

  final StoryController storyController;
  final MediaUploadController mediaUploadController;

  /// "Tanıtım Yap" adımı için: aynı görsel hem Story olarak paylaşılır hem de
  /// sponsorlu alan talebine iliştirilir. Bu fazda ödeme yok — talep yalnızca
  /// onay kuyruğuna düşer.
  final PromotionsController promotionsController;

  @override
  State<StoryComposerSheet> createState() => _StoryComposerSheetState();
}

class _StoryComposerSheetState extends State<StoryComposerSheet> {
  final _picker = ImagePicker();
  StoryVisibility _visibility = StoryVisibility.network;
  Duration _ttl = const Duration(hours: 24);
  String? _localId;
  Uint8List? _preview;
  bool _publishing = false;
  final Set<String> _excludedUserIds = <String>{};
  bool _saveAsHighlight = false;
  final TextEditingController _highlightTitleController =
      TextEditingController();

  bool _promote = false;
  PromotionPlacement _placement = PromotionPlacement.storySlot;
  DateTimeRange? _window;
  final TextEditingController _promotionTitleController =
      TextEditingController();
  final TextEditingController _promotionSubtitleController =
      TextEditingController();
  final TextEditingController _promotionNoteController =
      TextEditingController();

  /// Talebin gönderilebilir olması: başlık, gerekçe ve bir tarih aralığı.
  /// Görselin kendisi zaten Story'nin görseli, ayrıca seçtirilmiyor.
  bool get _promotionReady =>
      _window != null &&
      _promotionTitleController.text.trim().isNotEmpty &&
      _promotionNoteController.text.trim().isNotEmpty;

  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Kamerayla çek'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(source: source, imageQuality: 92);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final localId = '${DateTime.now().microsecondsSinceEpoch}-${image.name}';
    setState(() {
      _localId = localId;
      _preview = bytes;
    });
    await widget.mediaUploadController.upload(
      MediaUploadRequest(
        localUri: image.path,
        media: PostMediaUpload(
          localId: localId,
          type: PostMediaType.image,
          fileName: image.name,
          mimeType: image.mimeType ?? 'image/jpeg',
          sizeBytes: bytes.lengthInBytes,
        ),
      ),
    );
  }

  Future<void> _publish() async {
    final localId = _localId;
    if (localId == null) return;
    final media = widget.mediaUploadController.progressById[localId]?.media;
    if (media == null) return;
    setState(() => _publishing = true);
    try {
      final story = await widget.storyController.create(
        CreateStoryDraft(
          media: media,
          visibility: _visibility,
          ttl: _ttl,
          excludedUserIds: _excludedUserIds.toList(growable: false),
        ),
      );
      if (_saveAsHighlight) {
        final title = _highlightTitleController.text.trim();
        await widget.storyController.createHighlight(
          title: title.isEmpty ? 'Story' : title,
          visibility: _visibility,
          storyIds: [story.id],
        );
      }
      // Tanıtım talebi Story paylaşıldıktan sonra gönderilir ve ayrı yakalanır:
      // talep gönderilemediyse bile Story paylaşılmış olur, bunu "hiçbiri
      // olmadı" gibi göstermek yanlış olurdu.
      var promotionFailed = false;
      if (_promote && _promotionReady) {
        try {
          await widget.promotionsController.submit(
            PromotionRequestDraft(
              placement: _placement,
              title: _promotionTitleController.text.trim(),
              subtitle: _promotionSubtitleController.text.trim(),
              mediaId: media.id,
              startsAt: _window!.start,
              // Aralığın son günü de tanıtıma dahil: üye 5-7 Eylül seçtiyse
              // 7 Eylül akşamına kadar yayında kalmasını bekler.
              endsAt: _window!.end.add(const Duration(days: 1)),
              note: _promotionNoteController.text.trim(),
            ),
          );
        } catch (_) {
          promotionFailed = true;
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (_promote) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              promotionFailed
                  ? 'Story paylaşıldı ama tanıtım talebin gönderilemedi.'
                  : 'Tanıtım talebin incelenmek üzere gönderildi.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story paylaşımı gönderilemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _chooseWindow() async {
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 180)),
      initialDateRange: _window,
      helpText: 'Tanıtım tarih aralığı',
      saveText: 'Seç',
    );
    if (range == null || !mounted) return;
    if (range.duration.inDays >= _maxPromotionDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bir tanıtım en çok $_maxPromotionDays gün sürebilir.'),
        ),
      );
      return;
    }
    setState(() => _window = range);
  }

  @override
  void dispose() {
    _highlightTitleController.dispose();
    _promotionTitleController.dispose();
    _promotionSubtitleController.dispose();
    _promotionNoteController.dispose();
    super.dispose();
  }

  Future<void> _chooseExcludedMembers() async {
    try {
      final contacts = await widget.storyController.loadAudienceContacts();
      if (!mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gizlenecek bağlantı henüz yok.')),
        );
        return;
      }
      final selected = Set<String>.from(_excludedUserIds);
      final result = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  const Text(
                    'Bu kişilerden gizle',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
                    child: Text(
                      'Yalnızca mevcut bağlantıların burada görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (_, index) {
                        final contact = contacts[index];
                        return CheckboxListTile(
                          value: selected.contains(contact.id),
                          title: Text(contact.displayName),
                          onChanged: (value) => setSheetState(() {
                            value == true
                                ? selected.add(contact.id)
                                : selected.remove(contact.id);
                          }),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, selected),
                        child: const Text('Uygula'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _excludedUserIds
            ..clear()
            ..addAll(result);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gizlilik kişileri yüklenemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.mediaUploadController,
    builder: (context, _) {
      final progress = _localId == null
          ? null
          : widget.mediaUploadController.progressById[_localId!];
      final ready = progress?.media != null;
      final uploading =
          progress?.status == MediaUploadStatus.pending ||
          progress?.status == MediaUploadStatus.uploading;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          // Tanıtım adımı açıldığında sayfa ekrandan taşıyor; kaydırılabilir
          // olmasaydı "Paylaş" düğmesi klavyenin altında kalırdı.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8D5DF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Story oluştur',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Fotoğrafın güvenlik kontrolü tamamlanınca paylaşılır.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: uploading ? null : _pick,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 164,
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F0FA),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE0DCF7)),
                  ),
                  child: _preview == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              color: AppColors.primary,
                              size: 32,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Fotoğraf ekle',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_preview!, fit: BoxFit.cover),
                            if (uploading)
                              const ColoredBox(
                                color: Color(0x66000000),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (ready)
                              const Positioned(
                                right: 10,
                                top: 10,
                                child: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: AppColors.accentEmerald,
                                  child: Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              if (progress?.errorMessage case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Kimler görebilir?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SegmentedButton<StoryVisibility>(
                segments: const [
                  ButtonSegment(
                    value: StoryVisibility.network,
                    icon: Icon(Icons.people_outline),
                    label: Text('Arkadaşlar'),
                  ),
                  ButtonSegment(
                    value: StoryVisibility.public,
                    icon: Icon(Icons.public_outlined),
                    label: Text('Herkese açık'),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (value) =>
                    setState(() => _visibility = value.first),
              ),
              if (_visibility == StoryVisibility.network) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _chooseExcludedMembers,
                  icon: const Icon(Icons.person_off_outlined),
                  label: Text(
                    _excludedUserIds.isEmpty
                        ? 'Bazı kişilerden gizle'
                        : '${_excludedUserIds.length} kişiden gizli',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Ne kadar süre kalsın?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [6, 12, 24]
                    .map(
                      (hours) => ChoiceChip(
                        label: Text('$hours saat'),
                        selected: _ttl.inHours == hours,
                        onSelected: (_) =>
                            setState(() => _ttl = Duration(hours: hours)),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _saveAsHighlight,
                onChanged: (value) => setState(() => _saveAsHighlight = value),
                title: const Text(
                  'Profilimde öne çıkar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Süresi dolsa da profilinde kalır.'),
              ),
              if (_saveAsHighlight)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextField(
                    controller: _highlightTitleController,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Öne çıkan başlığı',
                      hintText: 'Örn. New York günlüğü',
                    ),
                  ),
                ),
              const Divider(height: 28),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _promote,
                onChanged: (value) => setState(() => _promote = value),
                title: const Text(
                  'Tanıtım yap',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Aynı görsel sponsorlu alanda gösterilsin. Ücret alınmaz; '
                  'talebin önce incelenir.',
                ),
              ),
              if (_promote) ...[
                const SizedBox(height: 8),
                const Text(
                  'Nerede gösterilsin?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                // Yalnızca üyenin isteyebileceği alanlar: "Öne Çıkan Kart"
                // panelden yerleştirilir, buradan talep edilemez.
                Wrap(
                  spacing: 8,
                  children: PromotionPlacement.requestable
                      .map(
                        (placement) => ChoiceChip(
                          label: Text(placement.label),
                          selected: _placement == placement,
                          onSelected: (_) =>
                              setState(() => _placement = placement),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promotionTitleController,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Örn. Paterson\'da Türk kahvaltısı',
                  ),
                ),
                TextField(
                  controller: _promotionSubtitleController,
                  maxLength: 90,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Alt başlık (isteğe bağlı)',
                  ),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _chooseWindow,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _window == null
                        ? 'Tarih aralığı seç'
                        : '${_formatDay(_window!.start)} - '
                              '${_formatDay(_window!.end)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promotionNoteController,
                  maxLength: 240,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Gerekçe',
                    hintText: 'Bu tanıtımı neden yapmak istiyorsun?',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      ready && !_publishing && (!_promote || _promotionReady)
                      ? _publish
                      : null,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    _publishing
                        ? 'Paylaşılıyor...'
                        : uploading
                        ? 'Güvenlik kontrolü sürüyor...'
                        : _promote
                        ? 'Paylaş ve tanıtım iste'
                        : 'Story paylaş',
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      );
    },
  );
}
