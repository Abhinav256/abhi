import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/chat_state.dart';
import 'chat_screen.dart';

// Brand colors
const Color _kPrimary = Color(0xFF0B4FD8);
const Color _kNavy = Color(0xFF08183A);
const Color _kBackground = Color(0xFFF6F8FC);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kMuted = Color(0xFF64748B);
const Color _kGreen = Color(0xFF10B981);

class ConversationsListScreen extends StatefulWidget {
  const ConversationsListScreen({super.key});

  @override
  State<ConversationsListScreen> createState() => _ConversationsListScreenState();
}

class _ConversationsListScreenState extends State<ConversationsListScreen>
    with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final ChatState _chatState = ChatState.instance;

  List<ChatConversationItem> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConversations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadConversations();
    }
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rawList = await _api.getChatConversations();
      if (!mounted) return;

      final items = rawList
          .map((e) => ChatConversationItem.fromJson(e))
          .where((c) => c.status != 'completed' && c.ride.status != 'completed')
          .toList();
      setState(() {
        _conversations = items;
        _isLoading = false;
      });
      _chatState.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(time.year, time.month, time.day);

    if (msgDate == today) {
      final hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final h = hour % 12 == 0 ? 12 : hour % 12;
      return '$h:$minute $period';
    } else if (today.difference(msgDate).inDays == 1) {
      return 'Yesterday';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[time.month - 1]} ${time.day}';
    }
  }

  List<ChatConversationItem> get _filteredConversations {
    if (_searchQuery.trim().isEmpty) return _conversations;
    final q = _searchQuery.toLowerCase();
    return _conversations.where((c) {
      final name = c.otherParticipant.displayName.toLowerCase();
      final route = '${c.ride.fromLocation} ${c.ride.toLocation}'.toLowerCase();
      final lastMsg = (c.lastMessage?.content ?? '').toLowerCase();
      return name.contains(q) || route.contains(q) || lastMsg.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Ride Messages',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _kNavy,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: _kNavy),
            onPressed: _loadConversations,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search / filter bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: Colors.white,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search chats, routes, passengers...',
                    hintStyle: TextStyle(color: _kMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: _kMuted, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: _kBorder),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadConversations,
                color: _kPrimary,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _kPrimary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load messages',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _kMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadConversations,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filteredConversations;

    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EEFD),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: _kPrimary),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No conversations yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _kNavy,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'When you book a ride or passengers book your ride, private 1-to-1 ride chats will appear here for seamless coordination.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: _kMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, index) => const Divider(height: 1, indent: 82, color: _kBorder),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildConversationTile(item);
      },
    );
  }

  Widget _buildConversationTile(ChatConversationItem item) {
    final other = item.otherParticipant;
    final ride = item.ride;
    final hasUnread = item.unreadCount > 0;
    final isDriver = other.role == 'driver';

    return Material(
      color: hasUnread ? const Color(0xFFF1F6FE) : Colors.white,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: item.id,
                initialConversation: item,
              ),
            ),
          );
          _loadConversations();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: isDriver ? const Color(0xFFE8F5E9) : const Color(0xFFE0EEFD),
                    child: Text(
                      other.displayName.isNotEmpty
                          ? other.displayName.substring(0, 1).toUpperCase()
                          : (isDriver ? 'D' : 'P'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDriver ? _kGreen : _kPrimary,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDriver ? const Color(0xFF10B981) : _kPrimary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        isDriver ? 'Driver' : 'Passenger',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Middle Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            other.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: _kNavy,
                            ),
                          ),
                        ),
                        Text(
                          _formatTimestamp(item.lastMessageAt),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color: hasUnread ? _kPrimary : _kMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Route & date chip
                    Row(
                      children: [
                        const Icon(Icons.route_rounded, size: 13, color: _kMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${ride.fromLocation} ➔ ${ride.toLocation}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Last message preview & unread badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.normal,
                              color: hasUnread ? _kNavy : _kMuted,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kPrimary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
