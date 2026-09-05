class UserProfile {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final parsedCreatedAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'].toString())
        : DateTime.now();

    final parsedUpdatedAt = json['updated_at'] != null
        ? DateTime.parse(json['updated_at'].toString())
        : parsedCreatedAt;

    final idStr = (json['id'] ?? json['user_id'] ?? '').toString();
    final nameStr = (json['name'] ?? json['full_name'] ?? '').toString();

    return UserProfile(
      id: idStr,
      userId: (json['user_id'] ?? idStr).toString(),
      fullName: nameStr,
      email: (json['email'] ?? '').toString(),
      avatarUrl: json['avatar_url'] as String?,
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': fullName,
      'full_name': fullName,
      'email': email,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? userId,
    String? fullName,
    String? email,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
