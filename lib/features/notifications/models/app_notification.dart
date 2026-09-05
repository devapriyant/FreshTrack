class AppNotification {
  final int id;
  final int foodItemId;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime expiryDate;
  final DateTime createdAt;
  final String? foodName;
  final String? category;
  final int? quantity;
  final String? storageLocation;
  final String? foodStatus;

  const AppNotification({
    required this.id,
    required this.foodItemId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.expiryDate,
    required this.createdAt,
    this.foodName,
    this.category,
    this.quantity,
    this.storageLocation,
    this.foodStatus,
  });

  bool get isExpiringSoon => type == 'expiring_soon';
  bool get isExpiresToday => type == 'expires_today';
  bool get isExpired => type == 'expired';

  static DateTime _parseDateOnly(dynamic value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final str = value.toString();
    final parsed = DateTime.parse(str);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: int.parse(json['id'].toString()),
      foodItemId: int.parse(
        (json['food_item_id'] ?? json['foodItemId']).toString(),
      ),
      type: (json['type'] ?? 'expiring_soon').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      isRead: json['is_read'] == true || json['isRead'] == true,
      expiryDate: _parseDateOnly(json['expiry_date'] ?? json['expiryDate']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
      foodName: (json['food_name'] ?? json['foodName']) as String?,
      category: json['category'] as String?,
      quantity: json['quantity'] != null
          ? int.tryParse(json['quantity'].toString())
          : null,
      storageLocation:
          (json['storage_location'] ?? json['storageLocation']) as String?,
      foodStatus: (json['food_status'] ?? json['foodStatus']) as String?,
    );
  }

  AppNotification copyWith({
    int? id,
    int? foodItemId,
    String? type,
    String? title,
    String? message,
    bool? isRead,
    DateTime? expiryDate,
    DateTime? createdAt,
    String? foodName,
    String? category,
    int? quantity,
    String? storageLocation,
    String? foodStatus,
  }) {
    return AppNotification(
      id: id ?? this.id,
      foodItemId: foodItemId ?? this.foodItemId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt ?? this.createdAt,
      foodName: foodName ?? this.foodName,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      storageLocation: storageLocation ?? this.storageLocation,
      foodStatus: foodStatus ?? this.foodStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'food_item_id': foodItemId,
      'type': type,
      'title': title,
      'message': message,
      'is_read': isRead,
      'expiry_date':
          '${expiryDate.year.toString().padLeft(4, '0')}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}',
      'created_at': createdAt.toIso8601String(),
      if (foodName != null) 'food_name': foodName,
      if (category != null) 'category': category,
      if (quantity != null) 'quantity': quantity,
      if (storageLocation != null) 'storage_location': storageLocation,
      if (foodStatus != null) 'food_status': foodStatus,
    };
  }
}
