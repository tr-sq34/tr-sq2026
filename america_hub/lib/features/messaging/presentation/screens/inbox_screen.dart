import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/messaging_controller.dart';
import '../../domain/entities/conversation.dart';
import 'conversation_screen.dart';
import '../widgets/create_group_sheet.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.controller});
  final MessagingController controller;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  int _currentTabIndex = 0; // 0: Inbox, 1: Unread, 2: Communities, 3: Requests
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFA5B4FC), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF0F172A) : AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header Bar
              _buildHeaderBar(isDarkMode),

              // Search Bar
              _buildSearchBar(isDarkMode),

              // Custom Tab Bar
              _buildTabBar(isDarkMode),

              // Main Content View
              Expanded(
                child: _buildTabContentView(isDarkMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: isDarkMode
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFFA5B4FC)],
                ).createShader(bounds),
                child: const Text(
                  'Mesajlar',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  onPressed: () => _showSnackBar('Yeni sohbet özelliği yakında'),
                  icon: const Icon(Icons.edit_rounded,
                      color: Color(0xFF6C5CE7)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.toLowerCase();
          });
        },
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Mesaj veya kişi ara...',
          hintStyle: TextStyle(
            color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontSize: 14,
          ),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 20, color: Color(0xFF94A3B8)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.cancel_rounded,
                      size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isDarkMode
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _buildTabButton(index: 0, label: 'Gelen Kutusu', isDarkMode: isDarkMode),
          _buildTabButton(
              index: 1,
              label: 'Okunmamış',
              badgeCount: widget.controller.unreadCount,
              isDarkMode: isDarkMode),
          _buildTabButton(index: 2, label: 'Topluluklar', isDarkMode: isDarkMode),
          _buildTabButton(
              index: 3,
              label: 'İstekler',
              badgeCount: widget.controller.requests.length,
              isDarkMode: isDarkMode),
        ],
      ),
    );
  }

  Widget _buildTabButton(
      {required int index, required String label, int badgeCount = 0, required bool isDarkMode}) {
    bool isSelected = _currentTabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _currentTabIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? const Color(0xFF334155) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (isDarkMode ? Colors.white : const Color(0xFF6C5CE7))
                        : (isDarkMode
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                  ),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color:
                        index == 3 ? const Color(0xFF6366F1) : const Color(0xFFF43F5E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContentView(bool isDarkMode) {
    switch (_currentTabIndex) {
      case 0:
        return _buildChatListView(onlyUnread: false, isDarkMode: isDarkMode);
      case 1:
        return _buildChatListView(onlyUnread: true, isDarkMode: isDarkMode);
      case 2:
        return _buildCommunitiesView(isDarkMode);
      case 3:
        return _buildRequestsView(isDarkMode);
      default:
        return const SizedBox();
    }
  }

  Widget _buildChatListView({required bool onlyUnread, required bool isDarkMode}) {
    List<Conversation> items = widget.controller.inbox;
    if (onlyUnread) {
      items = items.where((item) => item.unreadCount > 0).toList();
    }

    if (_searchQuery.isNotEmpty) {
      items = items
          .where((item) =>
              item.title.toLowerCase().contains(_searchQuery) ||
              item.preview.toLowerCase().contains(_searchQuery))
          .toList();
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mark_chat_read_rounded,
              size: 48,
              color: isDarkMode
                  ? const Color(0xFF475569)
                  : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'Mesaj bulunamadı',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final chat = items[index];
        final isSpecial = chat.kind == ConversationKind.request;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () async {
              HapticFeedback.selectionClick();
              await widget.controller.markRead(chat.id);
              if (!mounted) return;
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ConversationScreen(conversation: chat)));
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: chat.unreadCount > 0
                      ? const Color(0xFF6C5CE7).withValues(alpha: 0.4)
                      : (isDarkMode
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      if (isSpecial)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.luggage_rounded,
                              color: Colors.white, size: 24),
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.person_outline,
                              color: AppColors.primary),
                        ),
                      if (chat.unreadCount > 0)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDarkMode
                                    ? const Color(0xFF1E293B)
                                    : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              chat.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const Text(
                              '10:42', // Mock time
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          chat.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: chat.unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSpecial
                                ? const Color(0xFF6C5CE7)
                                : (isDarkMode
                                    ? const Color(0xFFCBD5E1)
                                    : const Color(0xFF475569)),
                          ),
                        ),
                        if (chat.contextLabel != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 10, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Text(
                                chat.contextLabel!,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Badge
                  if (chat.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF43F5E),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${chat.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommunitiesView(bool isDarkMode) {
    return Column(
      children: [
        // Create group action banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => CreateGroupSheet(controller: widget.controller)),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Grup Oluştur',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Community List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: widget.controller.groups.length,
            itemBuilder: (context, index) {
              final group = widget.controller.groups[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkMode
                        ? const Color(0xFF334155)
                        : const Color(0xFFF1F5F9),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE5DEFF), Color(0xFFD9D6FE)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.groups_outlined,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  size: 12, color: Color(0xFF6C5CE7)),
                              const SizedBox(width: 2),
                              Text(
                                '${group.city} • ${group.members} üye',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (group.isJoined)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981))
                    else
                      ElevatedButton(
                        onPressed: () => widget.controller.join(group.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDarkMode
                              ? const Color(0xFF6C5CE7).withValues(alpha: 0.2)
                              : const Color(0xFFEEF2FF),
                          foregroundColor: const Color(0xFF6C5CE7),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        child: const Text(
                          'Katıl',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsView(bool isDarkMode) {
    final items = widget.controller.requests;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  size: 48, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Yeni İstek Yok',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Tüm eşleşme isteklerini yanıtladınız.',
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isTravel = item.title.contains('Bavul');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode
                  ? const Color(0xFF334155)
                  : const Color(0xFFF1F5F9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                            isTravel
                                ? Icons.luggage_rounded
                                : Icons.volunteer_activism_outlined,
                            color: const Color(0xFF6C5CE7)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const Text(
                            'Özel Eşleşme İsteği',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Icon(Icons.more_horiz_rounded, color: Color(0xFF94A3B8)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.preview,
                style: const TextStyle(height: 1.4, fontSize: 13),
              ),
              if (item.contextLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    item.contextLabel!,
                    style: const TextStyle(
                        color: Color(0xFF6C5CE7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.controller
                          .respondToRequest(item.id, RequestDecision.declined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF43F5E),
                        side: const BorderSide(color: Color(0xFFF43F5E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Reddet',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final conversation = await widget.controller
                            .respondToRequest(item.id, RequestDecision.accepted);
                        if (!mounted || conversation == null) return;
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) =>
                                ConversationScreen(conversation: conversation)));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Kabul Et',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

