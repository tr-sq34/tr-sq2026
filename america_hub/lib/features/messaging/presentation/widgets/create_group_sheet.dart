import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../community/application/media_upload_controller.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/entities/post_media_upload.dart';
import '../../application/messaging_controller.dart';
import '../../domain/entities/conversation.dart';
import 'group_form_fields.dart';

/// Yeni grup kurma sayfası.
///
/// Eskiden burada tek satırlık bir form vardı ve fotoğraf düğmesi hiçbir şey
/// yapmıyordu: `onPressed:(){}`. Üye fotoğraf seçtiğini sanıp grubu kuruyor,
/// grup fotoğrafsız açılıyordu. Grubun ne için kurulduğunu yazacak bir yer de
/// yoktu; ad ve şehir, grubun nerede olduğunu söylüyor, ne olduğunu değil.
class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({
    super.key,
    required this.controller,
    required this.mediaUploadController,
  });

  final MessagingController controller;

  /// Grup fotoğrafı da akıştaki görsellerle aynı yoldan geçiyor: önce imzalı
  /// bağlantı, sonra depoya yazma, sonra güvenlik taraması. Bu yüzden fotoğraf
  /// "hazır" olana kadar grup kurulmuyor.
  final MediaUploadController mediaUploadController;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController(text: 'New York, NY');
  final _picker = ImagePicker();

  GroupPrivacy _privacy = GroupPrivacy.public;
  String? _localId;
  Uint8List? _preview;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  MediaUploadProgress? get _progress =>
      _localId == null ? null : widget.mediaUploadController.progressById[_localId!];

  bool get _uploading =>
      _progress?.status == MediaUploadStatus.pending ||
      _progress?.status == MediaUploadStatus.uploading;

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 88);
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

  Future<void> _chooseSource() async {
    final action = await showGroupPhotoActions(
      context,
      canRemove: _preview != null,
    );
    switch (action) {
      case GroupPhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case GroupPhotoAction.camera:
        await _pick(ImageSource.camera);
      case GroupPhotoAction.remove:
        final localId = _localId;
        if (localId != null) widget.mediaUploadController.remove(localId);
        setState(() {
          _localId = null;
          _preview = null;
        });
      case null:
        break;
    }
  }

  Future<void> _create() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final ok = await widget.controller.createGroup(
      name: _name.text,
      city: _city.text,
      privacy: _privacy,
      description: _description.text,
      imageUrl: _progress?.media?.url,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.pop(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.controller.errorMessage ??
              'Grup adı en az 3 karakter olmalı ve şehir bilgisi girilmeli.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.mediaUploadController,
    builder: (context, _) {
      final progress = _progress;
      // Fotoğraf seçilmediyse engel yok; seçildiyse taraması bitmeden grubun
      // kurulması, kurulan grubun fotoğrafsız kalması demek olurdu.
      final blockedByUpload = _localId != null && progress?.media == null;
      return Container(
        height: MediaQuery.sizeOf(context).height * .9,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const _Grabber(),
            _SheetHeader(
              title: 'Yeni grup',
              subtitle: 'Şehrindeki topluluğu bir araya getir.',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GroupAvatarPicker(
                        preview: _preview,
                        uploading: _uploading,
                        ready: progress?.media != null,
                        onTap: _uploading ? null : _chooseSource,
                      ),
                    ),
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
                    const SizedBox(height: 22),
                    GroupTextField(
                      controller: _name,
                      label: 'Grup adı',
                      hint: 'Örn. New Jersey Türk Aileleri',
                      icon: Icons.groups_outlined,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    GroupTextField(
                      controller: _description,
                      label: 'Grup açıklaması',
                      hint: 'Bu grup ne için kuruldu? Kimler katılmalı?',
                      icon: Icons.notes_rounded,
                      maxLength: 300,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    GroupTextField(
                      controller: _city,
                      label: 'Şehir / eyalet',
                      hint: 'Örn. Paterson, NJ',
                      icon: Icons.location_on_outlined,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle('Kimler katılabilir?'),
                    const SizedBox(height: 10),
                    GroupPrivacyChoice(
                      value: _privacy,
                      onChanged: (value) => setState(() => _privacy = value),
                    ),
                  ],
                ),
              ),
            ),
            _SubmitBar(
              label: _submitting
                  ? 'Grup kuruluyor...'
                  : _uploading
                  ? 'Fotoğrafın kontrolü sürüyor...'
                  : 'Grubu oluştur',
              busy: _submitting || _uploading,
              enabled: !_submitting &&
                  !blockedByUpload &&
                  _name.text.trim().length >= 3 &&
                  _city.text.trim().isNotEmpty,
              onPressed: _create,
            ),
          ],
        ),
      );
    },
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E4EC),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Kapat',
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: .2,
    ),
  );
}

/// Sayfanın dibine sabitlenmiş gönderme çubuğu: form uzasa da düğme
/// kaybolmuyor, klavye açıldığında da onun üstünde duruyor.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFEFEFF3))),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
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
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ),
  );
}
