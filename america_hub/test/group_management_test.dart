import 'package:america_hub/features/messaging/application/messaging_controller.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_messaging_repository.dart';
import 'package:america_hub/features/messaging/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

MessagingController _controller() =>
    MessagingController(repository: MockMessagingRepository());

void main() {
  test('kurulan grup aciklamasiyla birlikte listeye giriyor', () async {
    final controller = _controller();
    await controller.load();

    final ok = await controller.createGroup(
      name: 'Paterson Aileleri',
      city: 'Paterson, NJ',
      privacy: GroupPrivacy.private,
      description: '  Okul ve ev konusunda yardimlasma.  ',
      imageUrl: 'https://cdn.example/g.jpg',
    );

    expect(ok, isTrue);
    final group = controller.groups.first;
    expect(group.name, 'Paterson Aileleri');
    // Bosluklar kirpiliyor: kartta bastan bosluklu bir satir duruyordu.
    expect(group.description, 'Okul ve ev konusunda yardimlasma.');
    expect(group.imageUrl, 'https://cdn.example/g.jpg');
    expect(group.isOwner, isTrue);

    controller.dispose();
  });

  test('bos birakilan aciklama yazilmiyor', () async {
    final controller = _controller();
    // Bos bir metin alani ile "aciklama yok" ayni sey: sunucuya bos dize
    // gondermek, aciklamasi bos olan bir grup yaratirdi.
    await controller.createGroup(
      name: 'Austin Kahvecileri',
      city: 'Austin, TX',
      privacy: GroupPrivacy.public,
      description: '   ',
    );

    expect(controller.groups.first.description, isNull);

    controller.dispose();
  });

  test('duzenlemede dokunulmayan alan oldugu gibi kaliyor', () async {
    final controller = _controller();
    await controller.createGroup(
      name: 'New Jersey Turkleri',
      city: 'Newark, NJ',
      privacy: GroupPrivacy.public,
      description: 'Ilk aciklama',
      imageUrl: 'https://cdn.example/first.jpg',
    );
    final id = controller.groups.first.id;

    final ok = await controller.updateGroup(id, name: 'NJ Turkleri');

    expect(ok, isTrue);
    final group = controller.groups.firstWhere((item) => item.id == id);
    expect(group.name, 'NJ Turkleri');
    // Yalnizca ad degistiginde aciklamanin ve fotografin silinmesi, kurucunun
    // hic istemedigi bir kayipti.
    expect(group.description, 'Ilk aciklama');
    expect(group.imageUrl, 'https://cdn.example/first.jpg');

    controller.dispose();
  });

  test('acikca bosaltilan aciklama siliniyor', () async {
    final controller = _controller();
    await controller.createGroup(
      name: 'Bay Area Kosuculari',
      city: 'San Jose, CA',
      privacy: GroupPrivacy.public,
      description: 'Silinecek',
    );
    final id = controller.groups.first.id;

    await controller.updateGroup(id, description: null);

    expect(controller.groups.firstWhere((item) => item.id == id).description,
        isNull);

    controller.dispose();
  });

  test('davet edilen kisi uye sayilmiyor', () async {
    final controller = _controller();
    await controller.createGroup(
      name: 'Chicago Ogrencileri',
      city: 'Chicago, IL',
      privacy: GroupPrivacy.private,
    );
    final id = controller.groups.first.id;

    final status = await controller.inviteMember(id, 'user-elif');

    expect(status, GroupMembershipStatus.invited);
    final members = await controller.groupMembers(id);
    expect(members.any((member) => member.userId == 'user-elif'), isTrue);
    // Davet gonderildi, kabul edilmedi: sayac yerinde.
    expect(controller.groups.firstWhere((item) => item.id == id).members, 1);

    controller.dispose();
  });

  test('geri alinan davet uye sayacini dusurmuyor', () async {
    final controller = _controller();
    await controller.createGroup(
      name: 'Miami Turkleri',
      city: 'Miami, FL',
      privacy: GroupPrivacy.public,
    );
    final id = controller.groups.first.id;
    await controller.inviteMember(id, 'user-elif');

    final ok = await controller.removeMember(id, 'user-elif', wasJoined: false);

    expect(ok, isTrue);
    expect(await controller.groupMembers(id), hasLength(1));
    expect(controller.groups.firstWhere((item) => item.id == id).members, 1);

    controller.dispose();
  });

  test('bekleyen davet katilma istegi gibi gosterilmiyor', () {
    const invited = CommunityGroup(
      id: 'g',
      name: 'Grup',
      members: 4,
      city: 'Boston, MA',
      privacy: GroupPrivacy.private,
      membershipStatus: GroupMembershipStatus.invited,
    );

    // Davet edilen kisi icin onay zaten verilmis; "istegin onay bekliyor"
    // demek, karari kendisinde olan birine yanlis bir sey soylemek olurdu.
    expect(invited.isInvited, isTrue);
    expect(invited.isPending, isFalse);
    expect(invited.isJoined, isFalse);
  });
}
