import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/design/app_radius.dart';
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

/// Düzenleyicinin kendi paleti. Story bir fotoğraf işi: gövde koyu olunca
/// önizleme parlıyor ve üye yayınlanacak kareye bakıyor, formun beyazına değil.
/// Uygulamanın geri kalanı aydınlık kaldığı için bu renkler AppColors'a
/// taşınmadı - burası bilerek tek koyu yüzey.
const _canvas = Color(0xFF100F17);
const _panel = Color(0xFF1A1823);
const _panelBorder = Color(0xFF2A2836);
const _field = Color(0xFF221F2E);
const _mutedText = Color(0xFF9C97AC);

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

  Future<void> _pickFrom(ImageSource source) async {
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
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: AppRadius.sheet),
        ),
        builder: (sheetContext) => Theme(
          data: _composerTheme(context),
          child: StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .7,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    const _Grabber(),
                    const SizedBox(height: 14),
                    const Text(
                      'Bu kişilerden gizle',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: Text(
                        'Yalnızca mevcut bağlantıların burada görünür.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _mutedText),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (_, index) {
                          final contact = contacts[index];
                          return CheckboxListTile(
                            value: selected.contains(contact.id),
                            title: Text(
                              contact.displayName,
                              style: const TextStyle(color: Colors.white),
                            ),
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

  /// Koyu gövdenin içindeki Material bileşenleri (alan, onay kutusu, takvim)
  /// kendi renklerini buradan alsın diye tek bir tema. Tek tek renk vermek,
  /// bir bileşen eklendiğinde onun aydınlık kalmasıyla biterdi.
  ThemeData _composerTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        surface: _panel,
        onSurface: Colors.white,
      ),
      // Material'in kendi varsayilani aydinlik temanin siyah metni; koyu
      // yuzeyde okunmuyor. Her Text'e tek tek renk vermek yerine metin
      // olceginin tamami burada aciliyor.
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primaryLight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _field,
        hintStyle: const TextStyle(color: _mutedText),
        labelStyle: const TextStyle(color: _mutedText),
        floatingLabelStyle: const TextStyle(color: AppColors.primaryLight),
        counterStyle: const TextStyle(color: _mutedText, fontSize: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryLight),
        ),
      ),
    );
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
      final screen = MediaQuery.sizeOf(context);
      return Theme(
        data: _composerTheme(context),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Container(
            // Neredeyse tam ekran: Story bir fotoğraf işi, önizlemeye yer
            // gerekiyor. Yarım yükseklikte hem kare hem ayarlar sığmıyordu.
            height: screen.height * .94,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              // Bu yüzey sayfanın kendisine ait: sayfa saydam bir arka planla
              // açılıyor ve gövdenin kendi zemini olmazsa arkadaki akış
              // okunmaz bir şekilde içeriden görünüyor.
              color: _canvas,
              borderRadius: BorderRadius.vertical(top: AppRadius.sheet),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const _Grabber(),
                _Header(onClose: () => Navigator.pop(context)),
                Expanded(
                  // ListView degil: ayarlarin tamami her zaman kurulu olsun
                  // istiyoruz. Tembel bir liste, ekranin altinda kalan tanitim
                  // adimini hic insa etmiyor - o zaman ona kaydirmak da
                  // mumkun olmuyor.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(
                      children: [
                        _mediaStage(uploading: uploading, ready: ready),
                        if (progress?.errorMessage case final error?) ...[
                          const SizedBox(height: 10),
                          Text(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.accentRose,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _audienceSection(),
                        const SizedBox(height: 12),
                        _durationSection(),
                        const SizedBox(height: 12),
                        _highlightSection(),
                        const SizedBox(height: 12),
                        _promotionSection(),
                      ],
                    ),
                  ),
                ),
                _SendBar(
                  enabled: ready && !_publishing && (!_promote || _promotionReady),
                  label: _publishing
                      ? 'Paylaşılıyor...'
                      : uploading
                      ? 'Güvenlik kontrolü sürüyor...'
                      : _promote
                      ? 'Paylaş ve tanıtım iste'
                      : 'Story paylaş',
                  busy: _publishing || uploading,
                  onSend: _publish,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// Yayınlanacak kare, yayınlanacağı oranda: 9:16 dikey bir kart. Önizleme
  /// gerçek kırpmayı gösterdiği için üye "acaba nasıl çıkacak" diye
  /// paylaştıktan sonra bakmak zorunda kalmıyor.
  Widget _mediaStage({required bool uploading, required bool ready}) {
    final height = (MediaQuery.sizeOf(context).height * .34).clamp(210.0, 340.0);
    return Column(
      children: [
        Center(
          child: SizedBox(
            height: height,
            width: height * 9 / 16,
            child: Material(
              color: _panel,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: _panelBorder),
              ),
              child: InkWell(
                onTap: uploading ? null : () => _pickFrom(ImageSource.gallery),
                child: _preview == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppColors.primaryLight,
                            size: 34,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Fotoğraf ekle',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Dikey kare en iyi görünür',
                            style: TextStyle(color: _mutedText, fontSize: 11),
                          ),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_preview!, fit: BoxFit.cover),
                          if (uploading)
                            const ColoredBox(
                              color: Color(0x88000000),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.4,
                                ),
                              ),
                            ),
                          if (ready)
                            const Positioned(
                              right: 8,
                              top: 8,
                              child: _ReadyBadge(),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GhostButton(
              icon: Icons.photo_library_outlined,
              label: 'Galeri',
              onTap: uploading ? null : () => _pickFrom(ImageSource.gallery),
            ),
            const SizedBox(width: 10),
            _GhostButton(
              icon: Icons.photo_camera_outlined,
              label: 'Kamera',
              onTap: uploading ? null : () => _pickFrom(ImageSource.camera),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Fotoğrafın güvenlik kontrolü tamamlanınca paylaşılır.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _mutedText, fontSize: 12),
        ),
      ],
    );
  }

  Widget _audienceSection() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle('Kimler görebilir?'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Pill(
                icon: Icons.people_outline,
                label: 'Arkadaşlar',
                selected: _visibility == StoryVisibility.network,
                onTap: () =>
                    setState(() => _visibility = StoryVisibility.network),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Pill(
                icon: Icons.public_outlined,
                label: 'Herkese açık',
                selected: _visibility == StoryVisibility.public,
                onTap: () =>
                    setState(() => _visibility = StoryVisibility.public),
              ),
            ),
          ],
        ),
        if (_visibility == StoryVisibility.network) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _chooseExcludedMembers,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: Text(
                _excludedUserIds.isEmpty
                    ? 'Bazı kişilerden gizle'
                    : '${_excludedUserIds.length} kişiden gizli',
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _durationSection() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle('Ne kadar süre kalsın?'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final hours in const [6, 12, 24]) ...[
              Expanded(
                child: _Pill(
                  label: '$hours saat',
                  selected: _ttl.inHours == hours,
                  onTap: () => setState(() => _ttl = Duration(hours: hours)),
                ),
              ),
              if (hours != 24) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _highlightSection() => _Panel(
    child: Column(
      children: [
        _ToggleRow(
          title: 'Profilimde öne çıkar',
          subtitle: 'Süresi dolsa da profilinde kalır.',
          value: _saveAsHighlight,
          onChanged: (value) => setState(() => _saveAsHighlight = value),
        ),
        if (_saveAsHighlight)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _highlightTitleController,
              maxLength: 40,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Öne çıkan başlığı',
                hintText: 'Örn. New York günlüğü',
              ),
            ),
          ),
      ],
    ),
  );

  Widget _promotionSection() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToggleRow(
          title: 'Tanıtım yap',
          subtitle:
              'Aynı görsel sponsorlu alanda gösterilsin. Ücret alınmaz; '
              'talebin önce incelenir.',
          badge: 'SPONSORLU',
          value: _promote,
          onChanged: (value) => setState(() => _promote = value),
        ),
        if (_promote) ...[
          const SizedBox(height: 14),
          const _PanelTitle('Nerede gösterilsin?'),
          const SizedBox(height: 10),
          // Yalnızca üyenin isteyebileceği alanlar: "Öne Çıkan Kart"
          // panelden yerleştirilir, buradan talep edilemez.
          Row(
            children: [
              for (final placement in PromotionPlacement.requestable) ...[
                Expanded(
                  child: _Pill(
                    label: placement.label,
                    selected: _placement == placement,
                    onTap: () => setState(() => _placement = placement),
                  ),
                ),
                if (placement != PromotionPlacement.requestable.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _promotionTitleController,
            maxLength: 60,
            style: const TextStyle(color: Colors.white),
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
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Alt başlık (isteğe bağlı)',
            ),
          ),
          const SizedBox(height: 4),
          _DateRangeRow(
            label: _window == null
                ? 'Tarih aralığı seç'
                : '${_formatDay(_window!.start)} - ${_formatDay(_window!.end)}',
            chosen: _window != null,
            onTap: _chooseWindow,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _promotionNoteController,
            maxLength: 240,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Gerekçe',
              hintText: 'Bu tanıtımı neden yapmak istiyorsun?',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ],
    ),
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: _panelBorder,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          tooltip: 'Kapat',
        ),
        const Text(
          'Story oluştur',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _ReadyBadge extends StatelessWidget {
  const _ReadyBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.accentEmerald,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, color: Colors.white, size: 14),
        SizedBox(width: 4),
        Text(
          'Hazır',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

/// Koyu gövdedeki bir ayar bloğu. Her ayar kendi kartında durunca, tanıtım
/// adımı açıldığında sayfa uzasa bile hangi anahtarın neye ait olduğu
/// karışmıyor.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _panelBorder),
    ),
    child: child,
  );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 13,
      letterSpacing: .2,
      color: Colors.white,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primary : _field,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : _panelBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : _mutedText,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Başlığına dokununca da açılıp kapanan bir anahtar satırı. Anahtarın kendisi
/// küçük bir hedef; testler ve parmaklar metne dokunuyor.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? badge;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: _mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: _field,
        ),
      ],
    ),
  );
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _field,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _panelBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.date_range_outlined,
              size: 19,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: chosen ? Colors.white : _mutedText,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _mutedText),
          ],
        ),
      ),
    ),
  );
}

/// Sayfanın dibine sabitlenmiş gönderme çubuğu. Kaydırma alanının dışında
/// durduğu için form uzasa da düğme kaybolmuyor; klavye açıldığında da
/// onun üstünde kalıyor.
class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.enabled,
    required this.label,
    required this.busy,
    required this.onSend,
  });

  final bool enabled;
  final String label;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: _canvas,
      border: Border(top: BorderSide(color: _panelBorder)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onSend : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: _field,
            disabledForegroundColor: _mutedText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: _mutedText,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 19),
          label: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ),
  );
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _field,
    borderRadius: BorderRadius.circular(30),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _panelBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
