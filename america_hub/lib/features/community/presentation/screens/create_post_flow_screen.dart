import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../application/community_feed_controller.dart';
import '../../application/media_upload_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/create_post_draft.dart';
import '../../domain/entities/post_media_upload.dart';
import '../widgets/traveler_details_sheet.dart';
import '../widgets/post_purpose_grid.dart';

class CreatePostFlowScreen extends StatefulWidget {
  const CreatePostFlowScreen({super.key, required this.feedController, required this.mediaUploadController});
  final CommunityFeedController feedController;
  final MediaUploadController mediaUploadController;

  @override
  State<CreatePostFlowScreen> createState() => _CreatePostFlowScreenState();
}

class _CreatePostFlowScreenState extends State<CreatePostFlowScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  final List<_PickedMedia> _media = [];
  PostVisibility _visibility = PostVisibility.friendsOnly;
  CommentsPolicy _comments = CommentsPolicy.friendsOnly;
  CommunityPostPurpose _purpose = CommunityPostPurpose.standard;
  TravelerMatchDetails? _travelerMatch;
  String? _location;
  int _step = 0;
  bool _publishing = false;

  @override
  void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _pickImage() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (!mounted || files.isEmpty) return;
    for (final file in files.take(10 - _media.length)) {
      final bytes = await file.readAsBytes();
      _media.add(_PickedMedia(file: file, bytes: bytes, type: PostMediaType.image));
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseLocation() async {
    return _chooseLocationModern();
    final controller = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konum ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Mekân veya adres ara'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton.icon(onPressed: () => Navigator.of(dialogContext).pop('Mevcut konum'), icon: const Icon(Icons.my_location_outlined), label: const Text('Mevcut konum')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Ekle')),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty && mounted) setState(() => _location = result);
  }

  Future<void> _chooseLocationModern() async {
    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(initialValue: _location),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _location = result);
  }

  Future<void> _chooseAudience() async {
    final selected = await showModalBottomSheet<PostVisibility>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.people_outline_rounded), title: const Text('Arkadaşlar'), onTap: () => Navigator.pop(context, PostVisibility.friendsOnly)), ListTile(leading: const Icon(Icons.public_rounded), title: const Text('Herkese açık'), onTap: () => Navigator.pop(context, PostVisibility.public))])));
    if (selected != null && mounted) setState(() => _visibility = selected);
  }

  Future<void> _chooseComments() async {
    final selected = await showModalBottomSheet<CommentsPolicy>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final option in const [(CommentsPolicy.everyone, 'Herkes yorum yapabilir'), (CommentsPolicy.friendsOnly, 'Sadece arkadaşlar'), (CommentsPolicy.disabled, 'Yorumlara kapalı')]) ListTile(title: Text(option.$2), onTap: () => Navigator.pop(context, option.$1))])));
    if (selected != null && mounted) setState(() => _comments = selected);
  }

  String get _purposeLabel => switch (_purpose) {
        CommunityPostPurpose.standard => 'Standart paylaşım',
        CommunityPostPurpose.imeceHelp => 'İmece / Yardım',
        CommunityPostPurpose.travelerMatch => 'Bavulda Yer Var',
        CommunityPostPurpose.anonymousAdvice => 'Anonim dertleşme',
      };

  Future<void> _selectPurpose(CommunityPostPurpose purpose) async {
    if (purpose == CommunityPostPurpose.travelerMatch) {
      if (!mounted) return;
      final details = await showModalBottomSheet<TravelerMatchDetails>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TravelerDetailsSheet(initialValue: _travelerMatch),
      );
      if (!mounted || details == null) return;
      setState(() { _purpose = purpose; _travelerMatch = details; });
      return;
    }
    if (!mounted) return;
    setState(() { _purpose = purpose; _travelerMatch = null; });
  }

  Future<void> _choosePurpose() async {
    final choice = await showModalBottomSheet<CommunityPostPurpose>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Paylaşım türü', style: TextStyle(fontWeight: FontWeight.w800))),
          _purposeOption(sheetContext, CommunityPostPurpose.standard, Icons.article_outlined, 'Standart paylaşım', 'Akışta normal görünür'),
          _purposeOption(sheetContext, CommunityPostPurpose.imeceHelp, Icons.volunteer_activism_outlined, 'İmece / Yardım', 'Yakınındaki topluluktan destek iste'),
          _purposeOption(sheetContext, CommunityPostPurpose.travelerMatch, Icons.luggage_outlined, 'Bavulda Yer Var', 'Yolculuk ve küçük paket eşleşmesi oluştur'),
          _purposeOption(sheetContext, CommunityPostPurpose.anonymousAdvice, Icons.visibility_off_outlined, 'Anonim dertleşme', 'Adın görünmeden soru veya tavsiye paylaş'),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == CommunityPostPurpose.travelerMatch) {
      final route = await _chooseTravelerRoute();
      if (route == null || !mounted) return;
      setState(() { _purpose = choice; _travelerMatch = route; });
    } else {
      setState(() { _purpose = choice; _travelerMatch = null; });
    }
  }

  Widget _purposeOption(BuildContext context, CommunityPostPurpose value, IconData icon, String title, String subtitle) => ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title), subtitle: Text(subtitle),
        trailing: _purpose == value ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
        onTap: () => Navigator.pop(context, value),
      );

  Future<TravelerMatchDetails?> _chooseTravelerRoute() async {
    final from = TextEditingController(text: _travelerMatch?.from);
    final to = TextEditingController(text: _travelerMatch?.to);
    final note = TextEditingController(text: _travelerMatch?.note);
    final result = await showDialog<TravelerMatchDetails>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yolculuk bilgisi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: from, decoration: const InputDecoration(labelText: 'Nereden?')),
          TextField(controller: to, decoration: const InputDecoration(labelText: 'Nereye?')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Kısa not (isteğe bağlı)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, TravelerMatchDetails(from: from.text.trim(), to: to.text.trim(), travelAt: DateTime.now(), packageDetails: note.text.trim(), note: note.text.trim().isEmpty ? null : note.text.trim())), child: const Text('Ekle')),
        ],
      ),
    );
    from.dispose(); to.dispose(); note.dispose();
    if (result == null || result.from.isEmpty || result.to.isEmpty) return null;
    return result;
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      final draft = CreatePostDraft(
        message: _text.text,
        visibility: _visibility,
        commentsPolicy: _comments,
        location: _location == null ? null : PostLocation(placeId: _location!.toLowerCase().replaceAll(' ', '-'), displayName: _location!),
        media: _media.map((item) => PostMedia(id: item.file.name, type: item.type, url: item.file.path, previewBytes: item.bytes)).toList(growable: false),
        purpose: _purpose,
        travelerMatch: _travelerMatch,
      );
      if (draft.validationError case final error?) { throw ArgumentError(error); }
      await widget.feedController.createPost(draft);
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message?.toString() ?? 'Paylaşım geçersiz.')));
    } finally { if (mounted) setState(() => _publishing = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(onPressed: () => _step == 0 ? Navigator.pop(context) : setState(() => _step = 0), icon: const Icon(Icons.close_rounded)),
          title: Text(_step == 0 ? 'Paylaşım oluştur' : 'Paylaşımı gözden geçir', style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [_step == 0 ? TextButton(onPressed: _text.text.trim().isEmpty && _media.isEmpty ? null : () => setState(() => _step = 1), child: const Text('İleri')) : const SizedBox.shrink()],
        ),
        body: _step == 0 ? _composeStep() : _reviewStep(),
      );

  Widget _composeStep() => SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                controller: _text,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                scrollPhysics: const BouncingScrollPhysics(),
                style: const TextStyle(fontSize: 18, height: 1.45, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  hintText: 'Ne düşünüyorsun?',
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          if (_media.isNotEmpty)
            SizedBox(
              height: 126,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final media in _media)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(media.bytes, width: 112, height: 112, fit: BoxFit.cover)),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => setState(() => _media.remove(media)),
                              child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 15, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_location != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), child: Align(alignment: Alignment.centerLeft, child: InputChip(backgroundColor: const Color(0xFFEEF2FF), side: BorderSide.none, label: Text(_location!), onDeleted: () => setState(() => _location = null)))),
          if (_purpose != CommunityPostPurpose.standard) Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), child: Align(alignment: Alignment.centerLeft, child: InputChip(backgroundColor: const Color(0xFFF1ECFF), side: BorderSide.none, label: Text(_purposeLabel), onDeleted: () => setState(() { _purpose = CommunityPostPurpose.standard; _travelerMatch = null; })))),
          PostPurposeGrid(selected: _purpose, onSelected: _selectPurpose),
          Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEDEBF1)))), child: Row(children: [IconButton(onPressed: _pickImage, icon: const Icon(Icons.image_outlined, color: Color(0xFF6B7280))), IconButton(onPressed: () { _text.text += '@'; _text.selection = TextSelection.collapsed(offset: _text.text.length); }, icon: const Icon(Icons.alternate_email_rounded, color: Color(0xFF6B7280))), IconButton(onPressed: _chooseLocation, icon: const Icon(Icons.location_on_outlined, color: Color(0xFF6B7280))), const Spacer(), SizedBox(width: 82, child: AppButton(label: 'İleri', onPressed: _text.text.trim().isEmpty && _media.isEmpty ? null : () => setState(() => _step = 1)))])),
        ]),
      );

  Widget _reviewStep() => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x100E0B18), blurRadius: 18, offset: Offset(0, 6))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [const CircleAvatar(radius: 22, backgroundColor: Color(0xFFEEF2FF), child: Text('A', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_location == null ? 'Ahmet Yılmaz paylaşım yapıyor' : 'Ahmet Yılmaz ${_location!} konumunda', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const Text('Şimdi', style: TextStyle(color: AppColors.textMuted, fontSize: 12))]))]),
            ),
            if (_text.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: _ReviewTextPreview(message: _text.text)),
            if (_media.isNotEmpty) SizedBox(height: 128, width: double.infinity, child: Image.memory(_media.first.bytes, fit: BoxFit.cover)),
            if (_location != null) _locationPreview(),
          ]),
        ),
        const SizedBox(height: 20),
        _settingRow(icon: Icons.people_outline_rounded, title: 'Paylaşım kitlesi', value: _visibility == PostVisibility.public ? 'Herkese açık' : 'Arkadaşlar', onTap: _chooseAudience),
        _settingRow(icon: _comments == CommentsPolicy.disabled ? Icons.comments_disabled_outlined : Icons.mode_comment_outlined, title: 'Yorum ayarı', value: _comments == CommentsPolicy.everyone ? 'Herkes yorum yapabilir' : _comments == CommentsPolicy.friendsOnly ? 'Sadece arkadaşlar' : 'Yorumlara kapalı', onTap: _chooseComments),
        _settingRow(icon: Icons.ios_share_outlined, title: 'Ayrıca paylaş', value: 'Yakında', onTap: () {}),
        const SizedBox(height: 28), AppButton(label: 'Paylaş', onPressed: _publish, isLoading: _publishing, icon: Icons.send_rounded),
      ]);

  Widget _settingRow({required IconData icon, required String title, required String value, required VoidCallback onTap}) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), leading: Icon(icon, color: AppColors.textPrimary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(value, style: const TextStyle(color: AppColors.textMuted)), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap);

  Widget _locationPreview() => Container(
        height: 108,
        width: double.infinity,
        color: const Color(0xFFE8F3F5),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: CustomPaint(painter: _MapPreviewPainter())),
          const Icon(Icons.location_pin, color: Color(0xFFEF476F), size: 42),
          Positioned(
            left: 14,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_location!, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      );
}

class _PickedMedia {
  const _PickedMedia({required this.file, required this.bytes, required this.type});
  final XFile file;
  final Uint8List bytes;
  final PostMediaType type;
}

class _ReviewTextPreview extends StatelessWidget {
  const _ReviewTextPreview({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    const limit = 155;
    final isLong = message.runes.length > limit;
    final text = isLong ? '${String.fromCharCodes(message.runes.take(limit)).trimRight()}…' : message;
    return Text(text, maxLines: 4, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 15, height: 1.35, color: AppColors.textPrimary));
  }
}

class _MapPreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()..color = const Color(0xFFFFFFFF)..strokeWidth = 9..strokeCap = StrokeCap.round;
    final roadEdge = Paint()..color = const Color(0xFFD7E2E5)..strokeWidth = 11..strokeCap = StrokeCap.round;
    for (final offset in [0.16, .42, .72]) {
      canvas.drawLine(Offset(0, size.height * offset), Offset(size.width, size.height * (offset + .18)), roadEdge);
      canvas.drawLine(Offset(0, size.height * offset), Offset(size.width, size.height * (offset + .18)), road);
    }
    canvas.drawLine(Offset(size.width * .2, 0), Offset(size.width * .76, size.height), roadEdge);
    canvas.drawLine(Offset(size.width * .2, 0), Offset(size.width * .76, size.height), road);
    final water = Paint()..color = const Color(0xFFBDE6F2);
    canvas.drawCircle(Offset(size.width * .08, size.height * .55), size.width * .24, water);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
