import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/messaging_controller.dart';
import '../../domain/entities/conversation.dart';

/// Owner-only list of people waiting to be let into a private group.
///
/// The list is fetched when the sheet opens rather than kept on the group
/// object: only the owner may see it, and only while they are looking at it.
class JoinRequestsSheet extends StatefulWidget {
  const JoinRequestsSheet({
    super.key,
    required this.group,
    required this.controller,
  });

  final CommunityGroup group;
  final MessagingController controller;

  @override
  State<JoinRequestsSheet> createState() => _JoinRequestsSheetState();
}

class _JoinRequestsSheetState extends State<JoinRequestsSheet> {
  List<GroupJoinRequest> _requests = const [];
  final Set<String> _busy = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final requests = await widget.controller.joinRequests(widget.group.id);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'İstekler yüklenemedi. Lütfen tekrar deneyin.';
        _isLoading = false;
      });
    }
  }

  Future<void> _decide(GroupJoinRequest request, {required bool accept}) async {
    setState(() => _busy.add(request.userId));
    final ok = await widget.controller
        .decideJoinRequest(widget.group.id, request.userId, accept: accept);
    if (!mounted) return;
    setState(() {
      _busy.remove(request.userId);
      // The row is gone either way: accepting makes them a member, declining
      // drops the request entirely.
      if (ok) {
        _requests = _requests
            .where((item) => item.userId != request.userId)
            .toList(growable: false);
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İstek yanıtlanamadı. Lütfen tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Katılım istekleri',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                widget.group.name,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Bekleyen istek yok.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final request = _requests[index];
        final busy = _busy.contains(request.userId);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFF0E9FF),
            child: Icon(Icons.person_outline, color: AppColors.primary),
          ),
          // The projection is the only name source, and it is empty until the
          // requester verifies their email.
          title: Text(request.displayName ?? 'TurkSquare üyesi'),
          subtitle: Text(
            _stamp(request.requestedAt),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reddet',
                      onPressed: () => _decide(request, accept: false),
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFFEF4444)),
                    ),
                    IconButton(
                      tooltip: 'Kabul et',
                      onPressed: () => _decide(request, accept: true),
                      icon: const Icon(Icons.check_rounded,
                          color: Color(0xFF10B981)),
                    ),
                  ],
                ),
        );
      },
    );
  }

  static String _stamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month · $hour:$minute';
  }
}
