// lib/shared/models/user_model.dart
class UserModel {
  final int id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? status;
  final bool isAdmin;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.status,
    this.isAdmin = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phoneNumber: json['phone_number'] as String?,
        status: json['status'] as String?,
        isAdmin: json['is_admin'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'status': status,
        'is_admin': isAdmin,
      };

  // BUG FIX: Added missing initials getter used in home_page.dart
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  UserModel copyWith({
    int? id,
    String? fullName,
    String? email,
    String? phoneNumber,
    String? status,
    bool? isAdmin,
  }) =>
      UserModel(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        status: status ?? this.status,
        isAdmin: isAdmin ?? this.isAdmin,
      );
}