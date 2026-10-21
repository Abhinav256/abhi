import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/chat_state.dart';
import '../services/phone_call_service.dart';
import '../services/security_service.dart';
import '../services/session_service.dart';

// Brand Design Constants
const Color _kPrimary = Color(0xFF0B4FD8);
const Color _kNavy = Color(0xFF08183A);
const Color _kBackground = Color(0xFFF6F8FC);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kMuted = Color(0xFF64748B);
const Color _kGreen = Color(0xFF10B981);

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String? bookingId;
  final ChatConversationItem? initialConversation;

  const ChatScreen({
    super.key,
    this.conversationId,
    this.bookingId,
    this.initialConversation,
  }) : assert(
          conversationId != null || bookingId != null || initialConversation != null,
          'Either conversationId, bookingId, or initialConversation must be provided',
        );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final SessionService _session = SessionService();
  final ChatState _chatState = ChatState.instance;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? _conversationId;
  String? _bookingId;
  ChatParticipantSummary? _otherParticipant;
  ChatRideSummary? _ride;
  String _conversationStatus = 'active';
  String _bookingStatus = 'confirmed';
  String? _currentUserId;

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  bool _isRideCardExpanded = false;

  Timer? _pollingTimer;
  bool _isPolling = false;

  final List<String> _quickReplies = [
    "I'm on my way",
    "I've arrived",
    "Please share the pickup point",
    "I'll be there shortly",
    "Running 5 mins late",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollNewMessages();
    }
  }

  bool get _isReadOnly =>
      _conversationStatus == 'read_only' ||
      _conversationStatus == 'completed' ||
      _bookingStatus == 'cancelled' ||
      _bookingStatus == 'completed' ||
      _ride?.status == 'completed';

  Future<void> _initializeData() async {
    _currentUserId = await _session.getUserId();
    _bookingId = widget.bookingId ?? widget.initialConversation?.bookingId;

    // Use initial conversation if passed
    if (widget.initialConversation != null) {
      final c = widget.initialConversation!;
      _conversationId = c.id;
      _bookingId = c.bookingId;
      _otherParticipant = c.otherParticipant;
      _ride = c.ride;
      _conversationStatus = c.status;
      _bookingStatus = c.bookingStatus;
    } else {
      _conversationId = widget.conversationId;
    }

    // If conversation ID is still missing but bookingId is provided, get or create it
    if (_conversationId == null && widget.bookingId != null) {
      try {
        final res = await _api.getOrCreateChatConversation(
          bookingId: widget.bookingId!,
        );
        _conversationId = res['id']?.toString();
        _bookingId = res['booking_id']?.toString() ?? _bookingId;
        if (res['other_participant'] is Map) {
          _otherParticipant = ChatParticipantSummary.fromJson(
            Map<String, dynamic>.from(res['other_participant'] as Map),
          );
        }
        if (res['ride'] is Map) {
          _ride = ChatRideSummary.fromJson(
            Map<String, dynamic>.from(res['ride'] as Map),
          );
        }
        _conversationStatus = res['status']?.toString() ?? 'active';
        _bookingStatus = res['booking_status']?.toString() ?? 'confirmed';
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          });
        }
        return;
      }
    }

    if (_conversationId != null) {
      await _loadConversationDetailsAndMessages();
      _startPolling();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not find or create conversation.';
      });
    }
  }

  Future<void> _loadConversationDetailsAndMessages() async {
    if (_conversationId == null) return;
    try {
      // 1. Fetch conversation details if not fully known
      if (_otherParticipant == null || _ride == null) {
        final convData = await _api.getChatConversation(
          conversationId: _conversationId!,
        );
        if (convData['other_participant'] is Map) {
          _otherParticipant = ChatParticipantSummary.fromJson(
            Map<String, dynamic>.from(convData['other_participant'] as Map),
          );
        }
        if (convData['ride'] is Map) {
          _ride = ChatRideSummary.fromJson(
            Map<String, dynamic>.from(convData['ride'] as Map),
          );
        }
        _conversationStatus = convData['status']?.toString() ?? _conversationStatus;
        _bookingStatus = convData['booking_status']?.toString() ?? _bookingStatus;
        _bookingId = convData['booking_id']?.toString() ?? _bookingId;
      }

      // 2. Fetch messages (paginated, latest 50)
      final rawMsgs = await _api.getChatMessages(
        conversationId: _conversationId!,
        limit: 50,
      );

      final loaded = rawMsgs.map((e) => ChatMessage.fromJson(e)).toList();

      if (mounted) {
        setState(() {
          _messages = loaded;
          _isLoading = false;
          _errorMessage = null;
        });

        _scrollToBottom(animate: false);
      }

      // 3. Mark unread messages as read
      await _markAsRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollNewMessages();
    });
  }

  Future<void> _pollNewMessages() async {
    if (_conversationId == null || _isPolling || !mounted) return;
    _isPolling = true;

    try {
      final rawMsgs = await _api.getChatMessages(
        conversationId: _conversationId!,
        limit: 50,
      );
      final newMessages = rawMsgs.map((e) => ChatMessage.fromJson(e)).toList();

      if (!mounted) {
        _isPolling = false;
        return;
      }

      // Check if message count changed or new message IDs present
      final bool hasNew = newMessages.length != _messages.length ||
          (newMessages.isNotEmpty && _messages.isNotEmpty &&
              newMessages.last.id != _messages.last.id);

      if (hasNew) {
        setState(() {
          _messages = newMessages;
        });
        _scrollToBottom(animate: true);
        await _markAsRead();
      } else {
        // Also check if read receipts updated
        bool readUpdated = false;
        for (int i = 0; i < math.min(_messages.length, newMessages.length); i++) {
          if (_messages[i].isRead != newMessages[i].isRead) {
            readUpdated = true;
            break;
          }
        }
        if (readUpdated) {
          setState(() {
            _messages = newMessages;
          });
        }
      }
    } catch (_) {
      // Silently ignore polling network blips
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _markAsRead() async {
    if (_conversationId == null) return;
    try {
      final marked = await _api.markChatMessagesAsRead(
        conversationId: _conversationId!,
      );
      if (marked > 0) {
        _chatState.refresh();
      }
    } catch (_) {}
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _sendMessage(String text, {String messageType = 'text'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _conversationId == null || _isReadOnly) return;

    // Generate unique client message ID for idempotent deduplication
    final clientMsgId =
        'cli_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';

    // Optimistically add message to UI
    final tempMsg = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: _conversationId!,
      senderId: _currentUserId,
      senderRole: _otherParticipant?.role == 'driver' ? 'passenger' : 'driver',
      messageType: messageType,
      content: trimmed,
      clientMessageId: clientMsgId,
      isRead: false,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(tempMsg);
      _isSending = true;
    });
    _textController.clear();
    _scrollToBottom(animate: true);

    try {
      final sentData = await _api.sendChatMessage(
        conversationId: _conversationId!,
        content: trimmed,
        messageType: messageType,
        clientMessageId: clientMsgId,
      );

      final realMsg = ChatMessage.fromJson(sentData);

      if (mounted) {
        setState(() {
          // Replace temp message with server confirmed message
          final idx = _messages.indexWhere(
              (m) => m.clientMessageId == clientMsgId || m.id == tempMsg.id);
          if (idx != -1) {
            _messages[idx] = realMsg;
          } else {
            _messages.add(realMsg);
          }
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          // Remove temp message or show error
          _messages.removeWhere((m) => m.id == tempMsg.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showReportDialog() {
    final reasons = [
      'Inappropriate messages',
      'Harassment or abuse',
      'No-show / cancelled without notice',
      'Unsafe driving / vehicle issue',
      'Asking for off-app payment',
      'Other',
    ];
    String selectedReason = reasons[0];
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.report_problem_outlined, color: Colors.orange),
              SizedBox(width: 8),
              Text('Report User', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reporting ${_otherParticipant?.displayName ?? "this user"}. Your report will be kept confidential.',
                  style: const TextStyle(fontSize: 13, color: _kMuted),
                ),
                const SizedBox(height: 16),
                const Text('Reason',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _kBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedReason,
                      items: reasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedReason = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Details (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe what happened...',
                    hintStyle: const TextStyle(fontSize: 13, color: _kMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _kMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final targetId = _otherParticipant?.id;
                if (targetId == null) return;
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  await _api.reportChatUser(
                    userId: targetId,
                    reason: selectedReason,
                    description: descController.text.trim(),
                    rideId: _ride?.id,
                    conversationId: _conversationId,
                  );
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Report submitted. We will review it shortly.'),
                        backgroundColor: _kGreen,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(e.toString().replaceFirst('Exception: ', '')),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                }
              },
              child: const Text('Submit Report',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockConfirmation() {
    final otherName = _otherParticipant?.displayName ?? 'this user';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Block User?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to block $otherName? You will no longer be able to send or receive messages from them.',
          style: const TextStyle(color: _kMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final targetId = _otherParticipant?.id;
              if (targetId == null) return;
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              Navigator.pop(ctx);
              try {
                await _api.blockChatUser(userId: targetId, reason: 'User blocked');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('$otherName has been blocked.'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                  nav.pop(); // Exit chat screen
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCallPressed() async {
    if (_bookingStatus != 'confirmed' && _bookingStatus != 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone calls are only permitted for confirmed bookings.'),
          backgroundColor: _kNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bookingId = _bookingId ?? widget.bookingId ?? widget.initialConversation?.bookingId;
    String? targetPhone = _otherParticipant?.phone;
    String recipientName = _otherParticipant?.displayName ?? 'Recipient';

    // If phone number is not cached in other participant summary, fetch from authoritative contact endpoint
    if ((targetPhone == null || targetPhone.isEmpty) && bookingId != null && bookingId.isNotEmpty) {
      try {
        final contactData = await _api.getBookingContact(bookingId: bookingId);
        if (contactData != null) {
          targetPhone = contactData['phone']?.toString();
          final contactName = contactData['contact_name']?.toString();
          if (contactName != null && contactName.isNotEmpty) {
            recipientName = contactName;
          }
        }
      } catch (_) {}
    }

    if (targetPhone == null || targetPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contact number for $recipientName is not available.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final myPhone = await SecurityService().getUserPhone(userId: _currentUserId);

    if (mounted) {
      await PhoneCallService.makePhoneCall(
        context: context,
        phoneNumber: targetPhone,
        recipientName: recipientName,
        currentUserPhone: myPhone,
      );
    }
  }

  // -------------------------------------------------------------------------
  // UI Builders
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Compact Collapsible Ride Context Banner
            if (_ride != null) _buildRideContextBanner(),

            // Read-Only or Notice Warning
            if (_isReadOnly) _buildReadOnlyBanner(),

            // Chat Messages Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary),
                    )
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _messages.isEmpty
                          ? _buildEmptyState()
                          : _buildMessagesList(),
            ),

            // Quick Replies (only when active)
            if (!_isReadOnly && !_isLoading && _errorMessage == null)
              _buildQuickReplies(),

            // Bottom Input Bar (or Read-only footer)
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final other = _otherParticipant;
    final isDriver = other?.role == 'driver';

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      iconTheme: const IconThemeData(color: _kNavy),
      titleSpacing: 0,
      title: other == null
          ? const Text(
              'Chat',
              style: TextStyle(color: _kNavy, fontWeight: FontWeight.bold),
            )
          : Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      isDriver ? const Color(0xFFE8F5E9) : const Color(0xFFE0EEFD),
                  backgroundImage: (other.profilePhotoUrl != null &&
                          other.profilePhotoUrl!.isNotEmpty)
                      ? NetworkImage(other.profilePhotoUrl!)
                      : null,
                  child: (other.profilePhotoUrl == null ||
                          other.profilePhotoUrl!.isEmpty)
                      ? Text(
                          other.displayName.isNotEmpty
                              ? other.displayName.substring(0, 1).toUpperCase()
                              : (isDriver ? 'D' : 'P'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDriver
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFF0B4FD8),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        other.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kNavy,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDriver
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFE0EEFD),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isDriver ? 'Driver' : 'Passenger',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDriver
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFF0B4FD8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFF59E0B)),
                          Text(
                            other.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kNavy,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone_outlined, color: _kPrimary),
          tooltip: 'Call',
          onPressed: _handleCallPressed,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: _kNavy),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) {
            if (val == 'report') {
              _showReportDialog();
            } else if (val == 'block') {
              _showBlockConfirmation();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'report',
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, size: 20, color: Colors.orange),
                  SizedBox(width: 10),
                  Text('Report User'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'block',
              child: Row(
                children: [
                  Icon(Icons.block_outlined, size: 20, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Block User', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRideContextBanner() {
    final r = _ride!;
    final date = _formatDate(r.journeyDate);
    final time = _formatTime(r.departureTime);

    return Material(
      color: Colors.white,
      elevation: 0.5,
      child: InkWell(
        onTap: () {
          setState(() {
            _isRideCardExpanded = !_isRideCardExpanded;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kBorder, width: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_car_rounded,
                      size: 16, color: _kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r.fromLocation} → ${r.toLocation}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kNavy,
                      ),
                    ),
                  ),
                  Text(
                    '₹${r.pricePerSeat.toInt()}/seat',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isRideCardExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: _kMuted,
                  ),
                ],
              ),
              if (_isRideCardExpanded) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: _kMuted),
                    const SizedBox(width: 5),
                    Text(
                      '$date at $time',
                      style: const TextStyle(fontSize: 12, color: _kMuted),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: r.status == 'completed'
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: r.status == 'completed'
                              ? const Color(0xFF2E7D32)
                              : _kMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyBanner() {
    final String reason = _bookingStatus == 'cancelled'
        ? 'Booking cancelled • Messaging disabled'
        : 'Ride completed • Chat is read-only';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: const Color(0xFFFEF3C7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Text(
            reason,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Failed to load conversation',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _kNavy),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _initializeData();
              },
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF3FE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: _kPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Coordinate with ${_otherParticipant?.displayName ?? "the other person"}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share pickup spots, arrival times, and coordinate easily without sharing phone numbers.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _kMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.isMe(_currentUserId);

        if (msg.isSystem) {
          return _buildSystemMessage(msg);
        }

        // Show date header if first message or day changed
        bool showDateHeader = false;
        if (index == 0) {
          showDateHeader = true;
        } else {
          final prev = _messages[index - 1];
          if (prev.createdAt.day != msg.createdAt.day ||
              prev.createdAt.month != msg.createdAt.month ||
              prev.createdAt.year != msg.createdAt.year) {
            showDateHeader = true;
          }
        }

        Widget bubble;
        if (msg.isLocation) {
          bubble = _buildLocationCard(msg, isMe);
        } else {
          bubble = _buildMessageBubble(msg, isMe);
        }

        return Column(
          children: [
            if (showDateHeader) _buildDateHeader(msg.createdAt),
            bubble,
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      label = 'Today';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      label = 'Yesterday';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEDE9FE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Text(
            msg.content,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6D28D9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final timeStr = _formatTimeOnly(msg.createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: _kBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : _kNavy,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.75)
                        : _kMuted.withValues(alpha: 0.8),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: msg.isRead
                        ? const Color(0xFF67E8F9)
                        : Colors.white.withValues(alpha: 0.75),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(ChatMessage msg, bool isMe) {
    final lat = msg.latitude;
    final lng = msg.longitude;
    final mapUrl = msg.mapUrl;
    final timeStr = _formatTimeOnly(msg.createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMe ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: _kBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openMap(mapUrl, lat, lng),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header / preview block
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  color: isMe ? const Color(0xFF0944B8) : const Color(0xFFF1F6FE),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFECACA), width: 1),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFFDC2626),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shared Current Location',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isMe ? Colors.white : _kNavy,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              lat != null && lng != null
                                  ? '${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°'
                                  : 'Tap to view on Google Maps',
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : _kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom action banner: "Open in Maps"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: isMe ? _kPrimary : Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_rounded,
                            size: 16,
                            color: isMe ? const Color(0xFF93C5FD) : _kPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Open in Maps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMe ? Colors.white : _kPrimary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : _kMuted.withValues(alpha: 0.8),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              msg.isRead ? Icons.done_all : Icons.done,
                              size: 14,
                              color: msg.isRead
                                  ? const Color(0xFF67E8F9)
                                  : Colors.white.withValues(alpha: 0.75),
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
      ),
    );
  }

  Future<void> _openMap(String? mapUrl, double? lat, double? lng) async {
    Uri? uri;
    if (mapUrl != null && mapUrl.isNotEmpty) {
      uri = Uri.tryParse(mapUrl);
    } else if (lat != null && lng != null) {
      uri = Uri.tryParse('https://maps.google.com/?q=$lat,$lng');
    }
    if (uri == null) return;

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open maps: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Widget _buildQuickReplies() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickReplies.length,
        itemBuilder: (context, i) {
          final reply = _quickReplies[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              side: const BorderSide(color: Color(0xFFBFDBFE), width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              label: Text(
                reply,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _kPrimary,
                ),
              ),
              onPressed: () => _sendMessage(reply, messageType: 'quick_reply'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isReadOnly) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        color: Colors.white,
        child: const Text(
          'You cannot send new messages in this conversation.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: _kMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder, width: 0.8)),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isSending ? null : _showShareLocationSheet,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.location_on_outlined,
                  color: _kPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _kBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _kBorder),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(fontSize: 14, color: _kNavy),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(fontSize: 14, color: _kMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (val) => _sendMessage(val),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _kPrimary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isSending
                  ? null
                  : () => _sendMessage(_textController.text),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _formatDate(String raw) {
    if (raw.length >= 10) {
      final ymd = raw.substring(0, 10);
      final p = ymd.split('-');
      if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
      return ymd;
    }
    return raw;
  }

  String _formatTime(String raw) {
    if (raw.length >= 5) {
      return raw.substring(0, 5);
    }
    return raw;
  }

  String _formatTimeOnly(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final standardHour = h % 12 == 0 ? 12 : h % 12;
    return '$standardHour:$m $period';
  }

  void _showShareLocationSheet() {
    if (_isReadOnly) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareLocationModal(
        otherParticipantName:
            _otherParticipant?.displayName ?? 'the other person',
        onConfirmShare: (double lat, double lng, double accuracy) {
          final mapUrl = 'https://maps.google.com/?q=$lat,$lng';
          final payload = jsonEncode({
            'type': 'location',
            'latitude': lat,
            'longitude': lng,
            'accuracy': accuracy,
            'map_url': mapUrl,
            'label': 'Shared current location',
          });
          _sendMessage(payload, messageType: 'location');
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share Location Modal Bottom Sheet
// ---------------------------------------------------------------------------

class _ShareLocationModal extends StatefulWidget {
  final String otherParticipantName;
  final Function(double lat, double lng, double accuracy) onConfirmShare;

  const _ShareLocationModal({
    required this.otherParticipantName,
    required this.onConfirmShare,
  });

  @override
  State<_ShareLocationModal> createState() => _ShareLocationModalState();
}

enum _LocModalStep {
  initial,
  locating,
  ready,
  error,
}

class _ShareLocationModalState extends State<_ShareLocationModal> {
  _LocModalStep _step = _LocModalStep.initial;
  Position? _position;
  String? _errorMessage;
  bool _isPermanentlyDenied = false;
  bool _isServiceDisabled = false;

  Future<void> _detectLocation() async {
    setState(() {
      _step = _LocModalStep.locating;
      _errorMessage = null;
      _isPermanentlyDenied = false;
      _isServiceDisabled = false;
    });

    try {
      // 1. Check if device location services (GPS) are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _step = _LocModalStep.error;
          _isServiceDisabled = true;
          _errorMessage =
              'Location services (GPS) are turned off. Please turn on GPS to share your current location.';
        });
        return;
      }

      // 2. Check and request location permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _step = _LocModalStep.error;
          _errorMessage =
              'Location permission was denied. Please allow location access to share your pickup spot.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _step = _LocModalStep.error;
          _isPermanentlyDenied = true;
          _errorMessage =
              'Location permission is permanently denied in your device settings. Please open App Settings and grant location permission.';
        });
        return;
      }

      // 3. Acquire current GPS position with timeout
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } on TimeoutException {
        // Fallback to last known position if satellite fix timed out
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          if (!mounted) return;
          setState(() {
            _step = _LocModalStep.error;
            _errorMessage =
                'Location detection timed out. Please ensure you have a clear GPS signal and tap Retry.';
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _position = position;
        _step = _LocModalStep.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _LocModalStep.error;
        _errorMessage =
            'Unable to acquire location: ${e.toString().replaceFirst("Exception: ", "")}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Share Location',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: _kMuted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Content by step
          if (_step == _LocModalStep.initial) _buildInitialStep(),
          if (_step == _LocModalStep.locating) _buildLocatingStep(),
          if (_step == _LocModalStep.ready) _buildReadyStep(),
          if (_step == _LocModalStep.error) _buildErrorStep(),
        ],
      ),
    );
  }

  Widget _buildInitialStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F6FE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.security_rounded, color: _kPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'One-time location sharing only. No continuous background tracking.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _detectLocation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Color(0xFF16A34A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Current Location',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kNavy,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Send real-time GPS coordinates of your pickup spot',
                          style: TextStyle(fontSize: 12, color: _kMuted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _kMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLocatingStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Detecting your current location...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Acquiring accurate GPS coordinates from satellites',
            style: TextStyle(fontSize: 12, color: _kMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyStep() {
    final pos = _position!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F6FE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Location Detected',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pos.latitude.toStringAsFixed(5)}°, ${pos.longitude.toStringAsFixed(5)}°',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '✓ Accurate to ~${pos.accuracy.round()}m',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Will open in Google Maps',
                      style: TextStyle(fontSize: 11, color: _kMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Confirm sharing this location with ${widget.otherParticipantName}?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _kMuted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel', style: TextStyle(color: _kMuted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onConfirmShare(pos.latitude, pos.longitude, pos.accuracy);
                },
                icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Send Location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_off_rounded, color: Colors.red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Failed to access location.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close', style: TextStyle(color: _kMuted)),
              ),
            ),
            const SizedBox(width: 10),
            if (_isPermanentlyDenied)
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Open App Settings',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else if (_isServiceDisabled)
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    await Geolocator.openLocationSettings();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Open Location Settings',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _detectLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

