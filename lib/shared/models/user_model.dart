class UserModel {
  final int id;
  final String? phone_number;
  final String fullName;
  final String email;
  final bool isAdmin;
  final String status;
  final String? fcmToken;
  final String? phoneNumber;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    this.phone_number,
    required this.fullName,
    required this.email,
    required this.isAdmin,
    required this.status,
    this.fcmToken,
    this.phoneNumber,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        phone_number: json['phone_number'],
        fullName: json['full_name'] ?? '',
        email: json['email'] ?? '',
        isAdmin: json['is_admin'] ?? false,
        status: json['status'] ?? 'pending',
        fcmToken: json['fcm_token'],
        phoneNumber: json['phone_number'],
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone_number': phone_number,
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

  bool get isActive    => status == 'active';
  bool get isPending   => status == 'pending';
  bool get isSuspended => status == 'suspended';

  /// Affiche le numéro sous forme lisible : 20 XX XX XX
  String get formattedPhone {
    if (phoneNumber == null || phoneNumber!.length != 8) return phoneNumber ?? '—';
    return '${phoneNumber!.substring(0, 2)} '
        '${phoneNumber!.substring(2, 4)} '
        '${phoneNumber!.substring(4, 6)} '
        '${phoneNumber!.substring(6, 8)}';
  }

  UserModel copyWith({
    int? id,
    String? fullName,
    String? email,
    bool? isAdmin,
    String? status,
    String? fcmToken,
    String? phoneNumber,
  }) =>
      UserModel(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        isAdmin: isAdmin ?? this.isAdmin,
        status: status ?? this.status,
        fcmToken: fcmToken ?? this.fcmToken,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        createdAt: createdAt,
      );
}