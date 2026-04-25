export 'user_model.dart';

import 'user_model.dart';

class MessageModel {
  final int id;
  final int conversationId;
  final int senderId;
  final UserModel? sender;
  final String? body;
  final String type; // text, image, file, audio, video
  final String? mediaUrl;
  final String? mediaName;
  final int? mediaSize;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.sender,
    this.body,
    required this.type,
    this.mediaUrl,
    this.mediaName,
    this.mediaSize,
    required this.createdAt,
    this.deletedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'],
        conversationId: json['conversation_id'],
        senderId: json['sender_id'],
        sender:
            json['sender'] != null ? UserModel.fromJson(json['sender']) : null,
        body: json['body'],
        type: json['type'] ?? 'text',
        mediaUrl: json['media_url'],
        mediaName: json['media_name'],
        mediaSize: json['media_size'],
        createdAt: DateTime.parse(json['created_at']),
        deletedAt: json['deleted_at'] != null
            ? DateTime.tryParse(json['deleted_at'])
            : null,
      );

  bool get isDeleted => deletedAt != null;
  bool get hasMedia => mediaUrl != null;
  bool get isText => type == 'text';
  bool get isImage => type == 'image';
  bool get isFile => type == 'file';
  bool get isAudio => type == 'audio';
  bool get isVideo => type == 'video';
}
class ConversationModel {
  final int id;
  final String type; // direct, group
  final int? groupId;
  final GroupModel? group;
  final List<UserModel> participants;
  final MessageModel? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? lastReadAt;

  const ConversationModel({
    required this.id,
    required this.type,
    this.groupId,
    this.group,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) =>
      ConversationModel(
        id: json['id'],
        type: json['type'] ?? 'direct',
        groupId: json['group_id'],
        group:
            json['group'] != null ? GroupModel.fromJson(json['group']) : null,
        participants: (json['participants'] as List? ?? [])
            .map((p) => UserModel.fromJson(p))
            .toList(),
        lastMessage: json['last_message'] != null
            ? MessageModel.fromJson(json['last_message'])
            : null,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'])
            : null,
        lastReadAt: json['pivot']?['last_read_at'] != null
            ? DateTime.tryParse(json['pivot']['last_read_at'])
            : null,
      );

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';

  bool get hasUnread {
    if (lastMessage == null) return false;
    if (lastReadAt == null) return true;
    return lastMessage!.createdAt.isAfter(lastReadAt!);
  }

  String getDisplayName(int currentUserId) {
    if (isGroup) return group?.name ?? 'Groupe';
    final other =
        participants.where((p) => p.id != currentUserId).firstOrNull;
    return other?.fullName ?? 'Inconnu';
  }

  UserModel? getOtherParticipant(int currentUserId) {
    return participants.where((p) => p.id != currentUserId).firstOrNull;
  }
}

// ──────────────────────────────────────────────────────────────
// Group
// ──────────────────────────────────────────────────────────────
class GroupModel {
  final int id;
  final String name;
  final String? description;
  final String? avatar;
  final int createdBy;
  final UserModel? creator;
  final bool isDefault;
  final List<UserModel> members;
  final ConversationModel? conversation;

  const GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    required this.createdBy,
    this.creator,
    required this.isDefault,
    required this.members,
    this.conversation,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
        id: json['id'],
        name: json['name'] ?? '',
        description: json['description'],
        avatar: json['avatar'],
        createdBy: json['created_by'],
        creator: json['creator'] != null
            ? UserModel.fromJson(json['creator'])
            : null,
        isDefault: json['is_default'] ?? false,
        members: (json['members'] as List? ?? [])
            .map((m) => UserModel.fromJson(m))
            .toList(),
        conversation: json['conversation'] != null
            ? ConversationModel.fromJson(json['conversation'])
            : null,
      );

  String get initials => name.isNotEmpty ? name[0].toUpperCase() : 'G';
}

// ──────────────────────────────────────────────────────────────
// Call
// ──────────────────────────────────────────────────────────────
class CallModel {
  final int id;
  final int conversationId;
  final int callerId;
  final UserModel? caller;
  final String type; // audio, video
  final String status; // pending, active, ended, rejected
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;

  const CallModel({
    required this.id,
    required this.conversationId,
    required this.callerId,
    this.caller,
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.createdAt,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) => CallModel(
        id: json['id'],
        conversationId: json['conversation_id'],
        callerId: json['caller_id'],
        caller:
            json['caller'] != null ? UserModel.fromJson(json['caller']) : null,
        type: json['type'] ?? 'audio',
        status: json['status'] ?? 'pending',
        startedAt: json['started_at'] != null
            ? DateTime.tryParse(json['started_at'])
            : null,
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'])
            : null,
        createdAt: DateTime.parse(json['created_at']),
      );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';
  bool get isRejected => status == 'rejected';
  bool get isAudio => type == 'audio';
  bool get isVideo => type == 'video';

  Duration? get duration {
    if (startedAt == null || endedAt == null) return null;
    return endedAt!.difference(startedAt!);
  }

  String get durationDisplay {
    final d = duration;
    if (d == null) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ──────────────────────────────────────────────────────────────
// Notification
// ──────────────────────────────────────────────────────────────
class NotificationModel {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.data,
    this.readAt,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: json['id'],
        type: json['type'] ?? '',
        data: (json['data'] as Map<String, dynamic>?) ?? {},
        readAt:
            json['read_at'] != null ? DateTime.tryParse(json['read_at']) : null,
        createdAt: DateTime.parse(json['created_at']),
      );

  bool get isRead => readAt != null;
  String get title => data['title'] ?? data['sender_name'] ?? 'Notification';
  String get body => data['body'] ?? '';
}

// ──────────────────────────────────────────────────────────────
// Invitation
// ──────────────────────────────────────────────────────────────
class InvitationModel {
  final int id;
  final String email;
  final String token;
  final bool isUsed;
  final DateTime expiresAt;
  final UserModel? invitedBy;
  final DateTime createdAt;

  const InvitationModel({
    required this.id,
    required this.email,
    required this.token,
    required this.isUsed,
    required this.expiresAt,
    this.invitedBy,
    required this.createdAt,
  });

  factory InvitationModel.fromJson(Map<String, dynamic> json) =>
      InvitationModel(
        id: json['id'],
        email: json['email'],
        token: json['token'],
        isUsed: json['is_used'] ?? false,
        expiresAt: DateTime.parse(json['expires_at']),
        invitedBy: json['invited_by'] != null
            ? UserModel.fromJson(json['invited_by'])
            : null,
        createdAt: DateTime.parse(json['created_at']),
      );

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isValid => !isUsed && !isExpired;
}

// ──────────────────────────────────────────────────────────────
// Paginated Response
// ──────────────────────────────────────────────────────────────
class PaginatedResponse<T> {
  final List<T> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const PaginatedResponse({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  bool get hasMore => currentPage < lastPage;
}