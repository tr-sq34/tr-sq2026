import 'package:america_hub/features/messaging/application/messaging_controller.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_messaging_repository.dart';
import 'package:america_hub/features/messaging/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MessagingController controller;

  setUp(() async {
    controller = MessagingController(repository: MockMessagingRepository());
    await controller.load();
  });

  CommunityGroup groupById(String id) =>
      controller.groups.firstWhere((group) => group.id == id);

  test('joining a public group takes effect immediately', () async {
    final status = await controller.join('group-ny');

    expect(status, GroupMembershipStatus.joined);
    expect(groupById('group-ny').isJoined, isTrue);
    expect(groupById('group-ny').members, 1421);
  });

  test('joining a private group only queues a request', () async {
    final status = await controller.join('group-dev');

    expect(status, GroupMembershipStatus.requested);
    expect(groupById('group-dev').isPending, isTrue);
    expect(groupById('group-dev').isJoined, isFalse);
    // A pending request is not a member yet, so the count must not move.
    expect(groupById('group-dev').members, 318);
  });

  test('leaving a joined group releases the membership and the seat', () async {
    await controller.join('group-ny');

    expect(await controller.leave('group-ny'), isTrue);
    expect(groupById('group-ny').membershipStatus, GroupMembershipStatus.none);
    expect(groupById('group-ny').members, 1420);
  });

  test('a created group is owned by its creator and appears first', () async {
    final created = await controller.createGroup(
      name: 'Chicago Türkleri',
      city: 'Chicago, IL',
      privacy: GroupPrivacy.private,
    );

    expect(created, isTrue);
    expect(controller.groups.first.name, 'Chicago Türkleri');
    expect(controller.groups.first.isOwner, isTrue);
    expect(controller.groups.first.isJoined, isTrue);
  });

  test('a group name shorter than three characters is rejected locally', () async {
    expect(
      await controller.createGroup(name: 'AB', city: 'Boston, MA', privacy: GroupPrivacy.public),
      isFalse,
    );
    expect(controller.groups.length, 2);
  });
}
