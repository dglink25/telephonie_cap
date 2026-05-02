export 'user_model.dart' show UserModel;

import 'user_model.dart';

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
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        avatar: json['avatar'] as String?,
        createdBy: json['created_by'] as int? ?? 0,
        creator: json['creator'] != null
            ? UserModel.fromJson(json['creator'] as Map<String, dynamic>)
            : null,
        isDefault: json['is_default'] as bool? ?? false,
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => UserModel.fromJson(m as Map<String, dynamic>))
            .toList(),
        conversation: json['conversation'] != null
            ? ConversationModel.fromJson(
                json['conversation'] as Map<String, dynamic>)
            : null,
      );

  bool isAdmin(int userId) {
    if (userId == createdBy) return true;
    try {
      final member = members.firstWhere((m) => m.id == userId);
      return member.groupRole == 'admin';
    } catch (_) {
      return false;
    }
  }

  bool isMember(int userId) => members.any((m) => m.id == userId);

  String get initials {
    final words = name.trim().split(' ');
    if (words.isEmpty) return 'G';
    if (words.length == 1) return words[0][0].toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  GroupModel copyWith({
    int? id,
    String? name,
    String? description,
    String? avatar,
    int? createdBy,
    UserModel? creator,
    bool? isDefault,
    List<UserModel>? members,
    ConversationModel? conversation,
  }) =>
      GroupModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatar: avatar ?? this.avatar,
        createdBy: createdBy ?? this.createdBy,
        creator: creator ?? this.creator,
        isDefault: isDefault ?? this.isDefault,
        members: members ?? this.members,
        conversation: conversation ?? this.conversation,
      );
}

// ──────────────────────────────────────────────────────────────
// Message
// ──────────────────────────────────────────────────────────────
class MessageModel {
  final int id;
  final int conversationId;
  final int senderId;
  final UserModel? sender;
  final String? body;
  final String type;
  final String? mediaUrl;
  final String? mediaName;
  final int? mediaSize;
  final DateTime? readAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
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
    this.readAt,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as int,
        conversationId: json['conversation_id'] as int,
        senderId: json['sender_id'] as int,
        sender: json['sender'] != null
            ? UserModel.fromJson(json['sender'] as Map<String, dynamic>)
            : null,
        body: json['body'] as String?,
        type: json['type'] as String? ?? 'text',
        mediaUrl: json['media_url'] as String?,
        mediaName: json['media_name'] as String?,
        mediaSize: json['media_size'] as int?,
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
        deletedAt: json['deleted_at'] != null
            ? DateTime.tryParse(json['deleted_at'] as String)
            : null,
      );

  bool get isText => type == 'text';
  bool get isImage => type == 'image';
  bool get isFile => type == 'file';
  bool get isAudio => type == 'audio';
  bool get isVideo => type == 'video';
  bool get isDeleted => deletedAt != null;
  bool get hasMedia => mediaUrl != null;
  bool get isMedia => isImage || isFile || isAudio || isVideo;
}

// ──────────────────────────────────────────────────────────────
// Conversation
// ──────────────────────────────────────────────────────────────
class ConversationModel {
  final int id;
  final String type;
  final int? groupId;
  final GroupModel? group;
  final List<UserModel> participants;
  final MessageModel? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? lastReadAt;
  final bool? isFavorite;

  const ConversationModel({
    required this.id,
    required this.type,
    this.groupId,
    this.group,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt,
    this.isFavorite,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) =>
      ConversationModel(
        id: json['id'] as int,
        type: json['type'] as String? ?? 'direct',
        groupId: json['group_id'] as int?,
        group: json['group'] != null
            ? GroupModel.fromJson(json['group'] as Map<String, dynamic>)
            : null,
        participants: (json['participants'] as List<dynamic>? ?? [])
            .map((p) => UserModel.fromJson(p as Map<String, dynamic>))
            .toList(),
        lastMessage: json['last_message'] != null
            ? MessageModel.fromJson(
                json['last_message'] as Map<String, dynamic>)
            : null,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'] as String)
            : null,
        lastReadAt: (() {
          final pivot = json['pivot'] as Map<String, dynamic>?;
          final raw = pivot?['last_read_at'] as String?;
          return raw != null ? DateTime.tryParse(raw) : null;
        })(),
        isFavorite: (() {
          final pivot = json['pivot'] as Map<String, dynamic>?;
          final val = pivot?['is_favorite'];
          if (val == null) return false;
          if (val is bool) return val;
          if (val is int) return val == 1;
          return false;
        })(),
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
    final other = getOtherParticipant(currentUserId);
    return other?.fullName ?? 'Inconnu';
  }

  UserModel? getOtherParticipant(int currentUserId) {
    try {
      return participants.firstWhere((p) => p.id != currentUserId);
    } catch (_) {
      return participants.isNotEmpty ? participants.first : null;
    }
  }

  ConversationModel copyWith({
    int? id,
    String? type,
    int? groupId,
    GroupModel? group,
    List<UserModel>? participants,
    MessageModel? lastMessage,
    DateTime? lastMessageAt,
    DateTime? lastReadAt,
    bool? isFavorite,
  }) =>
      ConversationModel(
        id: id ?? this.id,
        type: type ?? this.type,
        groupId: groupId ?? this.groupId,
        group: group ?? this.group,
        participants: participants ?? this.participants,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

// ──────────────────────────────────────────────────────────────
// Call  ← CORRIGÉ : ajout de callee + isMissed
// ──────────────────────────────────────────────────────────────
class CallModel {
  final int id;
  final int conversationId;
  final int callerId;
  final UserModel? caller;
  final UserModel? callee;   // ← NOUVEAU
  final String type;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? duration;
  final DateTime createdAt;

  const CallModel({
    required this.id,
    required this.conversationId,
    required this.callerId,
    this.caller,
    this.callee,             // ← NOUVEAU
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.duration,
    required this.createdAt,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) => CallModel(
        id: json['id'] as int,
        conversationId: json['conversation_id'] as int,
        callerId: json['caller_id'] as int,
        caller: json['caller'] != null
            ? UserModel.fromJson(json['caller'] as Map<String, dynamic>)
            : null,
        callee: json['callee'] != null   // ← NOUVEAU
            ? UserModel.fromJson(json['callee'] as Map<String, dynamic>)
            : null,
        type: json['type'] as String? ?? 'audio',
        status: json['status'] as String? ?? 'pending',
        startedAt: json['started_at'] != null
            ? DateTime.tryParse(json['started_at'] as String)
            : null,
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        duration: json['duration'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  bool get isPending  => status == 'pending';
  bool get isActive   => status == 'active';
  bool get isEnded    => status == 'ended';
  bool get isRejected => status == 'rejected';
  bool get isMissed   => status == 'missed';   // ← NOUVEAU
  bool get isAudio    => type == 'audio';
  bool get isVideo    => type == 'video';

  CallModel copyWith({
    int? id,
    int? conversationId,
    int? callerId,
    UserModel? caller,
    UserModel? callee,       // ← NOUVEAU
    String? type,
    String? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? duration,
    DateTime? createdAt,
  }) =>
      CallModel(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        callerId: callerId ?? this.callerId,
        caller: caller ?? this.caller,
        callee: callee ?? this.callee,   // ← NOUVEAU
        type: type ?? this.type,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        duration: duration ?? this.duration,
        createdAt: createdAt ?? this.createdAt,
      );

  String get durationDisplay {
    if (duration == null) return '--';
    final m = duration! ~/ 60;
    final s = duration! % 60;
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
        id: json['id'] as String,
        type: json['type'] as String? ?? '',
        data: (json['data'] as Map<String, dynamic>?) ?? {},
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  bool get isRead => readAt != null;
  String get title =>
      data['title'] as String? ??
      data['sender_name'] as String? ??
      'Notification';
  String get body => data['body'] as String? ?? '';
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
        id: json['id'] as int,
        email: json['email'] as String,
        token: json['token'] as String,
        isUsed: json['is_used'] as bool? ?? false,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        invitedBy: json['invited_by'] != null
            ? UserModel.fromJson(json['invited_by'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isValid => !isUsed && !isExpired;
}

// ──────────────────────────────────────────────────────────────
// PaginatedResponse
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