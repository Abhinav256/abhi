import 'dart:convert';

/// Summary of the other user in the conversation (Driver or Passenger).
/// Phone numbers are never exposed for privacy.
class ChatParticipantSummary {
  final String id;
  final String fullName;
  final String nickname;
  final String gender;
  final double rating;
  final String? profilePhotoUrl;
  final String role; // 'driver' or 'passenger'
  final String? phone;

  const ChatParticipantSummary({
    required this.id,
    required this.fullName,
    required this.nickname,
    required this.gender,
    required this.rating,
    this.profilePhotoUrl,
    required this.role,
    this.phone,
  });

  String get displayName {
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (fullName.trim().isNotEmpty) return fullName.trim();
    return role == 'driver' ? 'Driver' : 'Passenger';
  }

  factory ChatParticipantSummary.fromJson(Map<String, dynamic> json) {
    final rawRating = json['rating'];
    final double ratingVal = (rawRating is num)
        ? rawRating.toDouble()
        : double.tryParse(rawRating?.toString() ?? '5.0') ?? 5.0;

    return ChatParticipantSummary(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      rating: ratingVal,
      profilePhotoUrl: json['profile_photo_url']?.toString(),
      role: json['role']?.toString() ?? 'passenger',
      phone: json['phone']?.toString(),
    );
  }
}

/// Compact read-only journey context displayed inside the chat.
class ChatRideSummary {
  final String id;
  final String fromLocation;
  final String toLocation;
  final String journeyDate;
  final String departureTime;
  final double pricePerSeat;
  final String status;
  final bool isWomenOnly;

  const ChatRideSummary({
    required this.id,
    required this.fromLocation,
    required this.toLocation,
    required this.journeyDate,
    required this.departureTime,
    required this.pricePerSeat,
    required this.status,
    required this.isWomenOnly,
  });

  factory ChatRideSummary.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price_per_seat'];
    final double priceVal = (rawPrice is num)
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0;

    return ChatRideSummary(
      id: json['id']?.toString() ?? '',
      fromLocation: json['from_location']?.toString() ?? '',
      toLocation: json['to_location']?.toString() ?? '',
      journeyDate: json['journey_date']?.toString() ?? '',
      departureTime: json['departure_time']?.toString() ?? '',
      pricePerSeat: priceVal,
      status: json['status']?.toString() ?? 'active',
      isWomenOnly: json['is_women_only'] == true,
    );
  }
}

/// A single persistent message in a chat conversation.
class ChatMessage {
  final String id;
  final String conversationId;
  final String? senderId;
  final String senderRole; // 'driver', 'passenger', 'system'
  final String messageType; // 'text', 'system', 'quick_reply'
  final String content;
  final String? clientMessageId;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    this.senderId,
    required this.senderRole,
    required this.messageType,
    required this.content,
    this.clientMessageId,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  bool isMe(String? currentUserId) {
    if (senderId == null || currentUserId == null) return false;
    return senderId == currentUserId;
  }

  bool get isSystem => senderRole == 'system' || messageType == 'system';
  bool get isLocation => messageType == 'location';

  Map<String, dynamic>? get locationData {
    if (!isLocation) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  double? get latitude {
    final raw = locationData?['latitude'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  double? get longitude {
    final raw = locationData?['longitude'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  double? get accuracy {
    final raw = locationData?['accuracy'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  String get mapUrl {
    final url = locationData?['map_url']?.toString();
    if (url != null && url.isNotEmpty) return url;
    final lat = latitude;
    final lng = longitude;
    if (lat != null && lng != null) {
      return 'https://maps.google.com/?q=$lat,$lng';
    }
    return '';
  }

  String get locationLabel {
    final lbl = locationData?['label']?.toString();
    if (lbl != null && lbl.isNotEmpty) return lbl;
    return 'Shared current location';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime parsedCreated = DateTime.now();
    if (json['created_at'] != null) {
      parsedCreated =
          DateTime.tryParse(json['created_at'].toString())?.toLocal() ??
              DateTime.now();
    }

    DateTime? parsedRead;
    if (json['read_at'] != null) {
      parsedRead = DateTime.tryParse(json['read_at'].toString())?.toLocal();
    }

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString(),
      senderRole: json['sender_role']?.toString() ?? 'passenger',
      messageType: json['message_type']?.toString() ?? 'text',
      content: json['content']?.toString() ?? '',
      clientMessageId: json['client_message_id']?.toString(),
      isRead: json['is_read'] == true,
      readAt: parsedRead,
      createdAt: parsedCreated,
    );
  }
}

/// A conversation item displayed in the conversations list.
class ChatConversationItem {
  final String id;
  final String rideId;
  final String bookingId;
  final String status; // 'active', 'archived', 'read_only'
  final DateTime lastMessageAt;
  final ChatParticipantSummary otherParticipant;
  final ChatRideSummary ride;
  final String bookingStatus;
  final int unreadCount;
  final ChatMessage? lastMessage;

  const ChatConversationItem({
    required this.id,
    required this.rideId,
    required this.bookingId,
    required this.status,
    required this.lastMessageAt,
    required this.otherParticipant,
    required this.ride,
    required this.bookingStatus,
    required this.unreadCount,
    this.lastMessage,
  });

  bool get isReadOnly =>
      status == 'read_only' || bookingStatus == 'cancelled';

  String get previewText {
    if (lastMessage == null) return 'Tap to chat with ${otherParticipant.displayName}';
    if (lastMessage!.isLocation) return '📍 Shared current location';
    return lastMessage!.content;
  }

  factory ChatConversationItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime = DateTime.now();
    if (json['last_message_at'] != null) {
      parsedTime =
          DateTime.tryParse(json['last_message_at'].toString())?.toLocal() ??
              DateTime.now();
    }

    ChatMessage? lm;
    if (json['last_message'] is Map) {
      lm = ChatMessage.fromJson(
          Map<String, dynamic>.from(json['last_message'] as Map));
    }

    return ChatConversationItem(
      id: json['id']?.toString() ?? '',
      rideId: json['ride_id']?.toString() ?? '',
      bookingId: json['booking_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      lastMessageAt: parsedTime,
      otherParticipant: ChatParticipantSummary.fromJson(
        json['other_participant'] is Map
            ? Map<String, dynamic>.from(json['other_participant'] as Map)
            : {},
      ),
      ride: ChatRideSummary.fromJson(
        json['ride'] is Map
            ? Map<String, dynamic>.from(json['ride'] as Map)
            : {},
      ),
      bookingStatus: json['booking_status']?.toString() ?? 'confirmed',
      unreadCount: json['unread_count'] is int
          ? json['unread_count'] as int
          : int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      lastMessage: lm,
    );
  }
}
