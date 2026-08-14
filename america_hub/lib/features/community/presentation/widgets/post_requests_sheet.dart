import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/community_special_request_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_special_request.dart';

/// Paylaşımına gelen istekler.
///
/// Bu ekran hiç yoktu. `getRequestsForPost` en baştan beri deponun sözleşmesinde
/// duruyordu ve hiçbir yerden çağrılmıyordu, çünkü sahibinin bakabileceği bir
/// yer yoktu: birisi "bavulunda yer var mı" diye yazıyor, kimse görmüyordu.
class PostRequestsSheet extends StatefulWidget {
  const PostRequestsSheet({
    super.key,
    required this.post,
    required this.controller,
  });

  final CommunityPost post;
  final CommunitySpecialRequestController controller;

  @override
  State<PostRequestsSheet> createState() => _PostRequestsSheetState();
}

class _PostRequestsSheetState extends State<PostRequestsSheet> {
  @override
  void initState() {
    super.initState();
    // Sayfa açılır açılmaz okunuyor: sahibi bu düğmeye zaten "kimler yazmış"
    // diye bakmak için dokundu.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.loadForPost(widget.post.id),
    );
  }

  Future<void> _answer(
    CommunitySpecialRequest request,
    CommunitySpecialRequestStatus status,
  ) async {
    final isDone = await widget.controller.updateStatus(request.id, status);
    if (!mounted || !isDone) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == CommunitySpecialRequestStatus.accepted
              ? 'İstek kabul edildi.'
              : 'İstek reddedildi.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final requests = widget.controller.requestsFor(widget.post.id);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8D5DF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Gelen istekler',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.post.purpose == CommunityPostPurpose.travelerMatch
                        ? 'Bavulunda yer isteyenler'
                        : 'Destek teklif edenler',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  if (widget.controller.errorMessage != null)
                    Text(
                      widget.controller.errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    )
                  else if (widget.controller.isLoading(widget.post.id) &&
                      requests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (requests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Henüz kimse istek göndermedi.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: requests.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _RequestTile(
                          request: requests[index],
                          onAnswer: _answer,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onAnswer});

  final CommunitySpecialRequest request;
  final void Function(
    CommunitySpecialRequest request,
    CommunitySpecialRequestStatus status,
  )
  onAnswer;

  @override
  Widget build(BuildContext context) {
    final isPending = request.status == CommunitySpecialRequestStatus.pending;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.senderName.isEmpty
                      ? 'TurkSquare üyesi'
                      : request.senderName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (!isPending)
                Text(
                  _statusLabel(request.status),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(request.message, style: const TextStyle(height: 1.4)),
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: () =>
                      onAnswer(request, CommunitySpecialRequestStatus.accepted),
                  child: const Text('Kabul et'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      onAnswer(request, CommunitySpecialRequestStatus.declined),
                  child: const Text('Reddet'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(CommunitySpecialRequestStatus status) =>
      switch (status) {
        CommunitySpecialRequestStatus.accepted => 'Kabul edildi',
        CommunitySpecialRequestStatus.declined => 'Reddedildi',
        CommunitySpecialRequestStatus.cancelled => 'Geri çekildi',
        CommunitySpecialRequestStatus.pending => 'Bekliyor',
      };
}
