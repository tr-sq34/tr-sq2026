import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../application/community_feed_controller.dart';
import '../../application/media_upload_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/create_post_draft.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../domain/entities/post_media_upload.dart';
import '../widgets/traveler_details_sheet.dart';

/// Editörün hangi işi yapmak için açıldığı.
///
/// Kısayollar ayrı ekranlar açmıyor: hepsi bu editörü açıyor, yalnızca açılış
/// ayarları değişiyor. Böylece "Anket" ile başlayan biri fikir değiştirip
/// fotoğraf da ekleyebiliyor.
enum PostComposerPreset { standard, question, poll, marketplace, travelerMatch }

/// Topluluğa paylaşım yapmanın tek yeri.
///
/// Eskiden iki ayrı editör vardı: alt bardaki ➕ tam ekran bir akış açıyordu,
/// akıştaki kutu ise kendi tabakasını. İkisi aynı şeyi farklı eksiklerle
/// yapıyordu — tabakada anket ve etiket yalnızca metnin sonuna `[Anket]`
/// yazıyor, tam ekran akışta ise anket hiç yoktu. Artık ikisi de burayı açıyor.
class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({
    super.key,
    required this.feedController,
    required this.mediaUploadController,
    this.viewer,
    this.preset = PostComposerPreset.standard,
    this.loadTaggablePeople,
  });

  final CommunityFeedController feedController;
  final MediaUploadController mediaUploadController;

  /// Paylaşımın kimin adına gideceği. Oturum yoksa null.
  final AppUser? viewer;
  final PostComposerPreset preset;

  /// Etiketlenebilecek kişiler. Uydurma bir liste tutmuyoruz: bağlandığı yer
  /// üyenin kendi çevresi. Sağlanmazsa etiket düğmesi hiç görünmüyor.
  final Future<List<TaggedUser>> Function()? loadTaggablePeople;

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  final List<_PickedMedia> _media = [];
  final List<TaggedUser> _taggedUsers = [];

  PostVisibility _visibility = PostVisibility.public;
  CommentsPolicy _comments = CommentsPolicy.everyone;
  CommunityPostPurpose _purpose = CommunityPostPurpose.standard;
  TravelerMatchDetails? _travelerMatch;
  PostLocation? _location;
  bool _publishing = false;

  /// Anket açıkken sorulan soru paylaşımın kendi metni: veritabanında anketin
  /// ayrı bir soru alanı yok, seçenekler gövdeye bağlı duruyor. İki ayrı alan
  /// göstermek, kaydedilmeyen bir alanı varmış gibi göstermek olurdu.
  bool _hasPoll = false;
  PollSelectionMode _pollMode = PollSelectionMode.single;
  Duration? _pollDuration;
  final List<TextEditingController> _pollOptions = [];

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    // Yükleme durumu ekranda görünmüyordu: küçük resim seçilir seçilmez
    // yerleşiyor, arkada yükleme başarısız olsa bile aynı duruyordu. Üye
    // fotoğrafı eklediğini görüyor, "Paylaş" diyor, akışta yalnızca yazı
    // çıkıyordu.
    widget.mediaUploadController.addListener(_onUploadsChanged);
    switch (widget.preset) {
      case PostComposerPreset.poll:
        _enablePoll();
      case PostComposerPreset.travelerMatch:
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _selectPurpose(CommunityPostPurpose.travelerMatch),
        );
      case PostComposerPreset.question:
      case PostComposerPreset.marketplace:
      case PostComposerPreset.standard:
        break;
    }
  }

  @override
  void dispose() {
    widget.mediaUploadController.removeListener(_onUploadsChanged);
    for (final option in _pollOptions) {
      option.dispose();
    }
    _text.dispose();
    super.dispose();
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  String get _hint => switch (widget.preset) {
    PostComposerPreset.question => 'Topluluğa ne sormak istiyorsun?',
    PostComposerPreset.poll => 'Anketin sorusu ne?',
    PostComposerPreset.marketplace => 'Ne satıyorsun? Kısaca anlat.',
    PostComposerPreset.travelerMatch => 'Yolculuğunu anlat.',
    PostComposerPreset.standard => 'Toplulukla ne paylaşmak istersin?',
  };

  String get _title => switch (widget.preset) {
    PostComposerPreset.question => 'Soru sor',
    PostComposerPreset.poll => 'Anket oluştur',
    PostComposerPreset.marketplace => 'Çarşı ilanı paylaş',
    PostComposerPreset.travelerMatch => 'Bavulda yer var',
    PostComposerPreset.standard => 'Yeni paylaşım',
  };

  bool get _canPublish =>
      !_publishing && (_text.text.trim().isNotEmpty || _media.isNotEmpty);

  void _enablePoll() {
    _hasPoll = true;
    if (_pollOptions.isEmpty) {
      _pollOptions.addAll([TextEditingController(), TextEditingController()]);
    }
  }

  void _togglePoll() => setState(() {
    if (_hasPoll) {
      _hasPoll = false;
      return;
    }
    _enablePoll();
  });

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    final selected = files.take(10 - _media.length).toList(growable: false);
    for (final file in selected) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(
        () => _media.add(
          _PickedMedia(
            id: file.name,
            path: file.path,
            bytes: bytes,
            type: PostMediaType.image,
          ),
        ),
      );
      await widget.mediaUploadController.upload(
        MediaUploadRequest(
          localUri: file.path,
          media: PostMediaUpload(
            localId: file.name,
            type: PostMediaType.image,
            fileName: file.name,
            mimeType: _mimeTypeOf(file),
            sizeBytes: bytes.length,
          ),
        ),
      );
    }
  }

  /// Seçilen dosyanın gerçek türü.
  ///
  /// Burada `image/jpeg` yazılı duruyordu. Galeriden gelen her dosya JPEG
  /// değil; ekran görüntüleri PNG ve seçicinin sıkıştırması PNG'de çalışmıyor,
  /// yani baytlar PNG kalıyor. Sunucuya "JPEG" diye beyan edilen bir PNG,
  /// taramayı yapan tarafta beyan ettiğinden başka bir dosya demek.
  String _mimeTypeOf(XFile file) {
    final name = (file.mimeType ?? file.name).toLowerCase();
    if (name.endsWith('.png') || name == 'image/png') return 'image/png';
    if (name.endsWith('.webp') || name == 'image/webp') return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _chooseLocation() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(initialValue: _location?.displayName),
    );
    if (!mounted || result == null || result.trim().isEmpty) return;
    setState(
      () => _location = PostLocation(
        placeId: result.trim().toLowerCase().replaceAll(' ', '-'),
        displayName: result.trim(),
      ),
    );
  }

  Future<void> _selectPurpose(CommunityPostPurpose purpose) async {
    if (purpose != CommunityPostPurpose.travelerMatch) {
      setState(() {
        _purpose = purpose;
        _travelerMatch = null;
      });
      return;
    }
    final details = await showModalBottomSheet<TravelerMatchDetails>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TravelerDetailsSheet(initialValue: _travelerMatch),
    );
    if (!mounted || details == null) return;
    setState(() {
      _purpose = purpose;
      _travelerMatch = details;
    });
  }

  Future<void> _chooseAudience() async {
    final selected = await showModalBottomSheet<PostVisibility>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              (PostVisibility.public, Icons.public_rounded, 'Herkese Açık',
                  'Akışta herkes görebilir'),
              (PostVisibility.friendsOnly, Icons.people_outline_rounded,
                  'Sadece arkadaşlar', 'Yalnızca bağlantıların görür'),
            ])
              ListTile(
                leading: Icon(option.$2, color: AppColors.primary),
                title: Text(option.$3),
                subtitle: Text(option.$4),
                trailing: _visibility == option.$1
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _visibility = selected);
  }

  Future<void> _chooseComments() async {
    final selected = await showModalBottomSheet<CommentsPolicy>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              (CommentsPolicy.everyone, 'Herkes yorum yapabilir'),
              (CommentsPolicy.friendsOnly, 'Sadece arkadaşlar'),
              (CommentsPolicy.disabled, 'Yorumlara kapalı'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: _comments == option.$1
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _comments = selected);
  }

  Future<void> _tagPeople() async {
    final load = widget.loadTaggablePeople;
    if (load == null) return;
    final people = await load();
    if (!mounted) return;
    final picked = await showModalBottomSheet<TaggedUser>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: people.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Text('Etiketlenecek kimse bulunamadı.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final person in people)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEDEAFF),
                        child: Text(
                          person.displayName.characters.first,
                          style: const TextStyle(
                            color: Color(0xFF705BE9),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(person.displayName),
                      trailing: _taggedUsers.any((item) => item.id == person.id)
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(sheetContext, person),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_taggedUsers.any((item) => item.id == picked.id)) return;
      _taggedUsers.add(picked);
    });
  }

  CommunityPoll? _buildPoll() {
    if (!_hasPoll) return null;
    final labels = _pollOptions
        .map((option) => option.text.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    return CommunityPoll(
      // Kalıcı kimlikleri sunucu veriyor; buradakiler yalnızca taslağın
      // kendi içinde seçenekleri ayırt etmek için.
      id: 'draft-poll',
      question: _text.text.trim(),
      options: [
        for (var index = 0; index < labels.length; index++)
          PollOption(id: 'draft-option-$index', label: labels[index]),
      ],
      selectionMode: _pollMode,
      endsAt: _pollDuration == null
          ? null
          : DateTime.now().add(_pollDuration!),
    );
  }

  /// Paylaşımın neden şu an gönderilemeyeceği; gönderilebiliyorsa null.
  ///
  /// Eskiden burada bir yedek yol vardı: sunucuya yüklenmiş görsel yoksa
  /// telefondaki dosya yolları `PostMedia` olarak drafta konuyordu. Sunucuya
  /// giden istek yalnızca gerçek medya kimliklerini taşıdığı için o yol hiçbir
  /// zaman bir görsel göndermedi; yalnızca "görsel eklendi" hissi verdi ve
  /// paylaşım sessizce yazıya dönüştü. Yükleme bitmediyse ya da başarısızsa
  /// paylaşımı durdurup nedenini söylemek, görseli düşürmekten iyidir.
  String? _uploadBlocker() {
    final progress = widget.mediaUploadController.progressById;
    for (final item in _media) {
      final state = progress[item.id];
      if (state == null) {
        return 'Görselin yüklemesi hiç başlamadı. Görseli kaldırıp tekrar ekler misin?';
      }
      switch (state.status) {
        case MediaUploadStatus.pending:
        case MediaUploadStatus.uploading:
          return 'Görsel hâlâ yükleniyor. Bitmesini bekleyip paylaşabilirsin.';
        case MediaUploadStatus.failed:
        case MediaUploadStatus.rejected:
          return state.errorMessage ?? 'Görsel yüklenemedi.';
        case MediaUploadStatus.ready:
          if (state.media == null) {
            return 'Görselin sunucudaki adresi alınamadı; paylaşım görselsiz '
                'gitmesin diye durduruldu.';
          }
      }
    }
    return null;
  }

  Future<void> _publish() async {
    if (_uploadBlocker() case final blocker?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blocker)));
      return;
    }
    final progress = widget.mediaUploadController.progressById;
    final draft = CreatePostDraft(
      message: _text.text,
      visibility: _visibility,
      commentsPolicy: _comments,
      // Sıra, üyenin seçtiği sıra: `readyMedia` bir Map'in değerlerinden
      // geliyor ve o sırayı korumak zorunda değil.
      media: [
        for (final item in _media) ?progress[item.id]?.media,
      ],
      taggedUsers: List.unmodifiable(_taggedUsers),
      location: _location,
      purpose: _purpose,
      travelerMatch: _travelerMatch,
      poll: _buildPoll(),
    );
    if (draft.validationError case final error?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _publishing = true);
    try {
      await widget.feedController.createPost(draft);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasPoll ? 'Anketin paylaşıldı.' : 'Paylaşımın yayında.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paylaşım gönderilemedi. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
          child: SizedBox(
            width: 96,
            child: AppButton(
              label: 'Paylaş',
              isLoading: _publishing,
              onPressed: _canPublish ? _publish : null,
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                _AuthorRow(
                  viewer: widget.viewer,
                  visibility: _visibility,
                  onTap: _chooseAudience,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  autofocus: true,
                  maxLength: CommunityPost.maxMessageLength,
                  maxLines: null,
                  minLines: 4,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: _hint,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
                if (_media.isNotEmpty) _mediaStrip(),
                if (_hasPoll) _pollEditor(),
                if (_location != null ||
                    _purpose != CommunityPostPurpose.standard ||
                    _taggedUsers.isNotEmpty)
                  _chips(),
              ],
            ),
          ),
          _toolbar(),
        ],
      ),
    ),
  );

  Widget _mediaStrip() => SizedBox(
    height: 108,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final item in _media)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    item.bytes,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                _uploadOverlay(item),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: () => setState(() {
                      _media.remove(item);
                      widget.mediaUploadController.remove(item.id);
                    }),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  /// Küçük resmin üzerindeki yükleme durumu.
  ///
  /// Hazır olan görselde hiçbir şey çizilmiyor: görüntünün kendisi zaten
  /// "tamam" diyor. Yüklenirken oran, başarısızken nedeni ve tek dokunuşluk
  /// bir "tekrar dene" var - çünkü başarısız yüklemenin çözümü paylaşımı
  /// tekrar denemek değil, yüklemeyi tekrar denemek.
  Widget _uploadOverlay(_PickedMedia item) {
    final state = widget.mediaUploadController.progressById[item.id];
    if (state == null || state.status == MediaUploadStatus.ready) {
      return const SizedBox.shrink();
    }
    final failed =
        state.status == MediaUploadStatus.failed ||
        state.status == MediaUploadStatus.rejected;
    return Positioned.fill(
      child: GestureDetector(
        onTap: failed
            ? () {
                widget.mediaUploadController.retry(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      state.errorMessage ?? 'Görsel yüklenemedi.',
                    ),
                  ),
                );
              }
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: failed ? .55 : .35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: failed
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Yüklenemedi\nTekrar dene',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      value: state.fraction <= 0 ? null : state.fraction,
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _pollEditor() => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'ANKET',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8B9AB3),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: _togglePoll,
              visualDensity: VisualDensity.compact,
              tooltip: 'Anketi kaldır',
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        const Text(
          'Soru, yukarıya yazdığın metnin kendisi.',
          style: TextStyle(fontSize: 11, color: Color(0xFF8B9AB3)),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _pollOptions.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pollOptions[index],
                    maxLength: 160,
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      hintText: '${index + 1}. seçenek',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
                if (_pollOptions.length > 2)
                  IconButton(
                    onPressed: () => setState(() {
                      _pollOptions.removeAt(index).dispose();
                    }),
                    tooltip: 'Seçeneği sil',
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
              ],
            ),
          ),
        if (_pollOptions.length < 4)
          TextButton.icon(
            onPressed: () =>
                setState(() => _pollOptions.add(TextEditingController())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Seçenek ekle'),
          ),
        const Divider(height: 20),
        Row(
          children: [
            const Text(
              'Çoklu seçim',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Switch(
              value: _pollMode == PollSelectionMode.multiple,
              onChanged: (value) => setState(
                () => _pollMode = value
                    ? PollSelectionMode.multiple
                    : PollSelectionMode.single,
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text(
              'Süre',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  for (final option in const [
                    (null, 'Süresiz'),
                    (Duration(days: 1), '1 gün'),
                    (Duration(days: 3), '3 gün'),
                    (Duration(days: 7), '1 hafta'),
                  ])
                    ChoiceChip(
                      label: Text(
                        option.$2,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _pollDuration == option.$1,
                      onSelected: (_) =>
                          setState(() => _pollDuration = option.$1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _chips() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (_location != null)
          InputChip(
            avatar: const Icon(Icons.location_on_outlined, size: 16),
            label: Text(_location!.displayName),
            onDeleted: () => setState(() => _location = null),
          ),
        if (_purpose != CommunityPostPurpose.standard)
          InputChip(
            avatar: const Icon(Icons.luggage_outlined, size: 16),
            label: Text(switch (_purpose) {
              CommunityPostPurpose.imeceHelp => 'İmece / Yardım',
              CommunityPostPurpose.travelerMatch => 'Bavulda Yer Var',
              CommunityPostPurpose.anonymousAdvice => 'Anonim dertleşme',
              CommunityPostPurpose.standard => '',
            }),
            onDeleted: () => setState(() {
              _purpose = CommunityPostPurpose.standard;
              _travelerMatch = null;
            }),
          ),
        for (final person in _taggedUsers)
          InputChip(
            avatar: const Icon(Icons.alternate_email_rounded, size: 16),
            label: Text(person.displayName),
            onDeleted: () =>
                setState(() => _taggedUsers.removeWhere((item) => item.id == person.id)),
          ),
      ],
    ),
  );

  Widget _toolbar() => Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFEDEBF1))),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarAction(
            icon: Icons.image_outlined,
            label: 'Fotoğraf',
            color: const Color(0xFF10B981),
            onTap: _pickPhotos,
          ),
          _ToolbarAction(
            icon: Icons.bar_chart_rounded,
            label: 'Anket',
            color: const Color(0xFF5D43D6),
            active: _hasPoll,
            onTap: _togglePoll,
          ),
          _ToolbarAction(
            icon: Icons.location_on_outlined,
            label: 'Konum',
            color: const Color(0xFFF05269),
            active: _location != null,
            onTap: _chooseLocation,
          ),
          if (widget.loadTaggablePeople != null)
            _ToolbarAction(
              icon: Icons.alternate_email_rounded,
              label: 'Etiket',
              color: const Color(0xFF5D43D6),
              active: _taggedUsers.isNotEmpty,
              onTap: _tagPeople,
            ),
          _ToolbarAction(
            icon: Icons.luggage_outlined,
            label: 'Bavulda Yer',
            color: const Color(0xFFF59E0B),
            active: _purpose == CommunityPostPurpose.travelerMatch,
            onTap: () => _selectPurpose(
              _purpose == CommunityPostPurpose.travelerMatch
                  ? CommunityPostPurpose.standard
                  : CommunityPostPurpose.travelerMatch,
            ),
          ),
          _ToolbarAction(
            icon: Icons.volunteer_activism_outlined,
            label: 'Destek İste',
            color: const Color(0xFF0EA5E9),
            active: _purpose == CommunityPostPurpose.imeceHelp,
            onTap: () => _selectPurpose(
              _purpose == CommunityPostPurpose.imeceHelp
                  ? CommunityPostPurpose.standard
                  : CommunityPostPurpose.imeceHelp,
            ),
          ),
          _ToolbarAction(
            icon: Icons.mode_comment_outlined,
            label: 'Yorumlar',
            color: const Color(0xFF64748B),
            onTap: _chooseComments,
          ),
        ],
      ),
    ),
  );
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.viewer,
    required this.visibility,
    required this.onTap,
  });
  final AppUser? viewer;
  final PostVisibility visibility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFEDEAFF),
        child: viewer == null
            ? const Icon(Icons.person_rounded, color: Color(0xFF705BE9))
            : Text(
                viewer!.initials,
                style: const TextStyle(
                  color: Color(0xFF705BE9),
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              viewer?.fullName ?? 'Sen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            // Kitle bir etiket değil, düğme: eskiden "Herkese Açık" yazan kutu
            // hiçbir şeye dokunmuyordu, dokunulunca da açılmıyordu.
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      visibility == PostVisibility.public
                          ? Icons.public_rounded
                          : Icons.people_outline_rounded,
                      size: 14,
                      color: const Color(0xFF4B5563),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      visibility == PostVisibility.public
                          ? 'Herkese Açık'
                          : 'Sadece arkadaşlar',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: .12) : Colors.white,
          border: Border.all(
            color: active ? color : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickedMedia {
  const _PickedMedia({
    required this.id,
    required this.path,
    required this.bytes,
    required this.type,
  });
  final String id;
  final String path;
  final Uint8List bytes;
  final PostMediaType type;
}
