import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../../community/application/media_upload_controller.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/entities/post_media_upload.dart';
import '../../../profile/application/friendship_controller.dart';
import '../../../profile/domain/entities/friendship.dart';
import '../../application/messaging_controller.dart';
import '../../domain/entities/conversation.dart';
import 'group_form_fields.dart';

/// Grup ayarları.
///
/// Grup kurulduktan sonra ona dokunmanın hiçbir yolu yoktu: adı yanlış yazan
/// kurucu grubu terk bile edemiyordu, birini çağırmak ya da çıkarmak ise hiç
/// mümkün değildi. Burası o eksiğin kapandığı yer — künye, üye listesi, davet
/// ve çıkarma tek sayfada.
class GroupSettingsSheet extends StatefulWidget {
  const GroupSettingsSheet({
    super.key,
    required this.group,
    required this.controller,
    required this.mediaUploadController,
    required this.friendshipController,
  });

  final CommunityGroup group;
  final MessagingController controller;
  final MediaUploadController mediaUploadController;

  /// Davet listesi arkadaşlardan geliyor. Buradan bir üye arama kutusu açmak,
  /// mesajlaşmanın dayandığı karşılıklı rızayı atlamak olurdu.
  final FriendshipController friendshipController;

  @override
  State<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<GroupSettingsSheet> {
  final _picker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _city;
  late CommunityGroup _group;

  List<GroupMember>? _members;
  String? _membersError;
  bool _loadingMembers = true;
  bool _editing = false;
  bool _saving = false;
  String? _localId;
  Uint8List? _preview;
  bool _photoCleared = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _name = TextEditingController(text: _group.name);
    _description = TextEditingController(text: _group.description ?? '');
    _city = TextEditingController(text: _group.city);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });
    try {
      final members = await widget.controller.groupMembers(_group.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Boş bir liste "bu grupta kimse yok" demek olurdu; oysa sorulan soru
      // cevapsız kaldı.
      setState(() {
        _membersError = 'Üye listesi yüklenemedi.';
        _loadingMembers = false;
      });
    }
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
      _photoCleared = false;
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

  Future<void> _choosePhoto() async {
    final action = await showGroupPhotoActions(
      context,
      canRemove: _preview != null || (_group.imageUrl != null && !_photoCleared),
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
          _photoCleared = true;
        });
      case null:
        break;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final description = _description.text.trim();
    final ok = await widget.controller.updateGroup(
      _group.id,
      name: _name.text.trim() == _group.name ? null : _name.text.trim(),
      city: _city.text.trim() == _group.city ? null : _city.text.trim(),
      description: description == (_group.description ?? '')
          ? CommunityGroup.unchanged
          : (description.isEmpty ? null : description),
      imageUrl: _photoCleared
          ? null
          : (_progress?.media?.url ?? CommunityGroup.unchanged),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      _snack(widget.controller.errorMessage ?? 'Değişiklikler kaydedilemedi.');
      return;
    }
    setState(() {
      _group = widget.controller.groups.firstWhere(
        (item) => item.id == _group.id,
        orElse: () => _group,
      );
      _editing = false;
      _photoCleared = false;
      _preview = null;
      _localId = null;
    });
    _snack('Grup bilgileri güncellendi.');
  }

  Future<void> _invite() async {
    final friend = await showModalBottomSheet<FriendSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteFriendSheet(
        controller: widget.friendshipController,
        alreadyIn: {for (final member in _members ?? const <GroupMember>[]) member.userId},
      ),
    );
    if (friend == null || !mounted) return;
    final status = await widget.controller.inviteMember(_group.id, friend.userId);
    if (!mounted) return;
    _snack(switch (status) {
      GroupMembershipStatus.invited =>
        '${friend.displayName} gruba davet edildi. Kabul edince listede görünecek.',
      GroupMembershipStatus.joined => '${friend.displayName} zaten grupta.',
      _ => widget.controller.errorMessage ?? 'Davet gönderilemedi.',
    });
    if (status != null) await _loadMembers();
  }

  Future<void> _remove(GroupMember member) async {
    final name = member.displayName ?? 'Bu üye';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(member.isInvitePending ? 'Daveti geri al' : 'Üyeyi çıkar'),
        content: Text(
          member.isInvitePending
              ? '$name için gönderdiğin davet iptal edilsin mi?'
              : '$name gruptan çıkarılsın mı? Sohbeti bir daha okuyamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentRose),
            child: Text(member.isInvitePending ? 'Daveti geri al' : 'Çıkar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.controller.removeMember(
      _group.id,
      member.userId,
      wasJoined: !member.isInvitePending,
    );
    if (!mounted) return;
    if (!ok) {
      _snack(widget.controller.errorMessage ?? 'Üye çıkarılamadı.');
      return;
    }
    setState(() {
      _members = [
        for (final item in _members ?? const <GroupMember>[])
          if (item.userId != member.userId) item,
      ];
      _group = widget.controller.groups.firstWhere(
        (item) => item.id == _group.id,
        orElse: () => _group,
      );
    });
    _snack(member.isInvitePending ? 'Davet geri alındı.' : '$name gruptan çıkarıldı.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.mediaUploadController,
    builder: (context, _) => Container(
      height: MediaQuery.sizeOf(context).height * .9,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E4EC),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                if (_editing) ..._editForm() else ..._profile(),
                const SizedBox(height: 22),
                _membersSection(),
              ],
            ),
          ),
          if (_editing) _saveBar(),
        ],
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Grup ayarları',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        if (_group.isOwner && !_editing)
          TextButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Düzenle'),
          ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Kapat',
        ),
      ],
    ),
  );

  List<Widget> _profile() {
    final image = appImageProvider(_group.imageUrl);
    return [
      Center(
        child: CircleAvatar(
          radius: 46,
          backgroundColor: const Color(0xFFF3F0FF),
          backgroundImage: image,
          child: image == null
              ? const Icon(Icons.groups_rounded,
                  size: 38, color: AppColors.primary)
              : null,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        _group.name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _group.privacy == GroupPrivacy.private
                ? Icons.lock_outline_rounded
                : Icons.public_rounded,
            size: 14,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${_group.privacy == GroupPrivacy.private ? 'Gizli grup' : 'Açık grup'}'
              ' · ${_group.city} · ${_group.members} üye',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAEAF1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grup açıklaması',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              // Açıklama yoksa yokluğunu söylüyor; boş bir kutu, açıklamanın
              // yüklenemediğiyle karışıyordu.
              _group.description?.trim().isNotEmpty ?? false
                  ? _group.description!
                  : _group.isOwner
                  ? 'Henüz açıklama yazmadın. "Düzenle" ile ekleyebilirsin.'
                  : 'Bu grup için açıklama yazılmamış.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _group.description?.trim().isNotEmpty ?? false
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _editForm() => [
    Center(
      child: GroupAvatarPicker(
        preview: _preview,
        existingUrl: _photoCleared ? null : _group.imageUrl,
        uploading: _uploading,
        ready: _progress?.media != null,
        onTap: _uploading ? null : _choosePhoto,
      ),
    ),
    if (_progress?.errorMessage case final error?) ...[
      const SizedBox(height: 10),
      Text(
        error,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.accentRose, fontSize: 12),
      ),
    ],
    const SizedBox(height: 20),
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
    const SizedBox(height: 12),
    // Gizlilik burada yok ve nedeni yazılı: sessizce eksik bırakılmış bir alan
    // gibi görünmesin.
    Row(
      children: [
        const Icon(Icons.info_outline, size: 15, color: Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _group.privacy == GroupPrivacy.private
                ? 'Bu grup gizli. Gizlilik ayarı sonradan değiştirilemiyor: '
                      'katılmış üyeler geçmişi zaten okumuş oluyor.'
                : 'Bu grup herkese açık. Gizlilik ayarı sonradan '
                      'değiştirilemiyor: katılmış üyeler geçmişi zaten okumuş oluyor.',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  ];

  Widget _membersSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Üyeler',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (_group.isOwner)
            TextButton.icon(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Davet et'),
            ),
        ],
      ),
      const SizedBox(height: 6),
      if (_loadingMembers)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        )
      else if (_membersError != null)
        _MembersNotice(
          icon: Icons.cloud_off_rounded,
          message: _membersError!,
          actionLabel: 'Tekrar dene',
          onAction: _loadMembers,
        )
      else if ((_members ?? const []).isEmpty)
        _MembersNotice(
          icon: Icons.person_outline,
          message: _group.isOwner
              ? 'Grupta şu an yalnız sensin. "Davet et" ile arkadaşlarını çağırabilirsin.'
              : 'Bu grupta gösterilecek başka üye yok.',
        )
      else
        for (final member in _members!)
          _MemberTile(
            member: member,
            canRemove: _group.isOwner && !member.isOwner,
            onRemove: () => _remove(member),
          ),
    ],
  );

  Widget _saveBar() {
    final blockedByUpload = _localId != null && _progress?.media == null;
    return Container(
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
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _editing = false;
                        _name.text = _group.name;
                        _city.text = _group.city;
                        _description.text = _group.description ?? '';
                        _preview = null;
                        _localId = null;
                        _photoCleared = false;
                      }),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed:
                    _saving || blockedByUpload || _name.text.trim().length < 3 ||
                        _city.text.trim().isEmpty
                    ? null
                    : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  _saving
                      ? 'Kaydediliyor...'
                      : _uploading
                      ? 'Fotoğraf kontrol ediliyor...'
                      : 'Kaydet',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  final GroupMember member;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFFF3F0FF),
      child: Icon(
        member.isInvitePending
            ? Icons.hourglass_empty_rounded
            : Icons.person_outline,
        size: 20,
        color: AppColors.primary,
      ),
    ),
    title: Text(
      // Ad izdüşüme ulaşmadıysa uydurulmuyor.
      member.displayName ?? 'TurkSquare üyesi',
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
    subtitle: Text(
      member.isOwner
          ? 'Grup kurucusu'
          : member.isInvitePending
          ? 'Daveti bekliyor'
          : 'Üye',
      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
    ),
    trailing: canRemove
        ? IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_outlined, size: 20),
            color: const Color(0xFF94A3B8),
            tooltip: member.isInvitePending ? 'Daveti geri al' : 'Gruptan çıkar',
          )
        : null,
  );
}

class _MembersNotice extends StatelessWidget {
  const _MembersNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FB),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEAEAF1)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 26, color: const Color(0xFF94A3B8)),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 8),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

/// Davet edilecek kişiyi seçtiren liste. Zaten grupta olanlar sönük ve
/// dokunulamaz: kurucunun aynı kişiye ikinci kez davet göndermesinin tek
/// sonucu, sunucudan gelen anlamsız bir hata olurdu.
class _InviteFriendSheet extends StatefulWidget {
  const _InviteFriendSheet({required this.controller, required this.alreadyIn});

  final FriendshipController controller;
  final Set<String> alreadyIn;

  @override
  State<_InviteFriendSheet> createState() => _InviteFriendSheetState();
}

class _InviteFriendSheetState extends State<_InviteFriendSheet> {
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
              'Gruba davet et',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Yalnızca arkadaşlarını davet edebilirsin.',
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
        final inGroup = widget.alreadyIn.contains(friend.userId);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: !inGroup,
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
          subtitle: Text(inGroup ? 'Zaten grupta' : friend.placeLabel),
          onTap: inGroup
              ? null
              : () => Navigator.of(context).pop<FriendSummary>(friend),
        );
      },
    );
  }
}
