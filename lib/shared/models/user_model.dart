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
        // Accepte phone_number ou phoneNumber depuis l'API
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