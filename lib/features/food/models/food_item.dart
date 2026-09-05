enum FoodExpiryState { fresh, expiringSoon, expiresToday, expired }

enum ExpiryFilter {
  all,
  active,
  fresh,
  expiringSoon,
  expiresToday,
  expired,
  consumed,
  discarded,
}

class FoodItem {
  final int id;
  final int userId;
  final String foodName;
  final String? category;
  final int quantity;
  final DateTime? purchaseDate;
  final DateTime expiryDate;
  final String? storageLocation;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FoodItem({
    required this.id,
    required this.userId,
    required this.foodName,
    this.category,
    this.quantity = 1,
    this.purchaseDate,
    required this.expiryDate,
    this.storageLocation,
    this.status = 'active',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime _parseDateOnly(dynamic value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final str = value.toString();
    // Support YYYY-MM-DD or ISO strings
    final parsed = DateTime.parse(str);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime? _parseNullableDateOnly(dynamic value) {
    if (value == null) return null;
    return _parseDateOnly(value);
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: int.parse(json['id'].toString()),
      userId: int.parse((json['user_id'] ?? json['userId']).toString()),
      foodName: (json['food_name'] ?? json['foodName'] ?? '').toString(),
      category: json['category'] as String?,
      quantity: int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      purchaseDate: _parseNullableDateOnly(
        json['purchase_date'] ?? json['purchaseDate'],
      ),
      expiryDate: _parseDateOnly(json['expiry_date'] ?? json['expiryDate']),
      storageLocation:
          (json['storage_location'] ?? json['storageLocation']) as String?,
      status: (json['status'] as String?)?.toLowerCase() ?? 'active',
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toCreatePayload() {
    return {
      'food_name': foodName.trim(),
      if (category != null && category!.trim().isNotEmpty)
        'category': category!.trim(),
      'quantity': quantity,
      if (purchaseDate != null) 'purchase_date': _formatDateOnly(purchaseDate!),
      'expiry_date': _formatDateOnly(expiryDate),
      if (storageLocation != null && storageLocation!.trim().isNotEmpty)
        'storage_location': storageLocation!.trim(),
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'food_name': foodName.trim(),
      'category': (category != null && category!.trim().isNotEmpty)
          ? category!.trim()
          : null,
      'quantity': quantity,
      'purchase_date': purchaseDate != null
          ? _formatDateOnly(purchaseDate!)
          : null,
      'expiry_date': _formatDateOnly(expiryDate),
      'storage_location':
          (storageLocation != null && storageLocation!.trim().isNotEmpty)
          ? storageLocation!.trim()
          : null,
      'notes': (notes != null && notes!.trim().isNotEmpty)
          ? notes!.trim()
          : null,
    };
  }

  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  FoodExpiryState get expiryState {
    final days = daysUntilExpiry;
    if (days < 0) return FoodExpiryState.expired;
    if (days == 0) return FoodExpiryState.expiresToday;
    if (days <= 3) return FoodExpiryState.expiringSoon;
    return FoodExpiryState.fresh;
  }

  bool get isExpired => daysUntilExpiry < 0;
  bool get isExpiringToday => daysUntilExpiry == 0;
  bool get isExpiringSoon => daysUntilExpiry >= 1 && daysUntilExpiry <= 3;
  bool get isFresh => daysUntilExpiry > 3;

  bool get isActive => status == 'active';
  bool get isConsumed => status == 'consumed';
  bool get isDiscarded => status == 'discarded';

  String get expiryStatusDisplay {
    if (status == 'consumed') return 'Consumed';
    if (status == 'discarded') return 'Discarded';

    final days = daysUntilExpiry;
    if (days < 0) {
      final absDays = days.abs();
      return absDays == 1 ? 'Expired yesterday' : 'Expired $absDays days ago';
    }
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires tomorrow';
    if (days <= 3) return 'Expires in $days days';
    return 'Fresh ($days days left)';
  }

  FoodItem copyWith({
    int? id,
    int? userId,
    String? foodName,
    String? category,
    int? quantity,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    String? storageLocation,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      foodName: foodName ?? this.foodName,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      expiryDate: expiryDate ?? this.expiryDate,
      storageLocation: storageLocation ?? this.storageLocation,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          foodName == other.foodName &&
          category == other.category &&
          quantity == other.quantity &&
          purchaseDate == other.purchaseDate &&
          expiryDate == other.expiryDate &&
          storageLocation == other.storageLocation &&
          status == other.status &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    foodName,
    category,
    quantity,
    purchaseDate,
    expiryDate,
    storageLocation,
    status,
    notes,
  );
}
