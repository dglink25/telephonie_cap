class UserModel {
  final int id;
  final String fullName;
  final String email;
  final bool isAdmin;
  final String status;
  final String? fcmToken;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isAdmin,
    required this.status,
    this.fcmToken,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        isAdmin: json['is_admin'] ?? false,
        status: json['status'] ?? 'pending',
        fcmToken: json['fcm_token'],
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'is_admin': isAdmin,
        'status': status,
        'fcm_token': fcmToken,
        'created_at': createdAt?.toIso8601String(),
      };

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isSuspended => status == 'suspended';

  UserModel copyWith({
    int? id,
    String? fullName,
    String? email,
    bool? isAdmin,
    String? status,
    String? fcmToken,
  }) =>
      UserModel(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        isAdmin: isAdmin ?? this.isAdmin,
        status: status ?? this.status,
        fcmToken: fcmToken ?? this.fcmToken,
        createdAt: createdAt,
      );
}