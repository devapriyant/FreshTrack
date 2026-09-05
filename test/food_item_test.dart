import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/features/food/models/food_item.dart';

void main() {
  group('FoodItem Model Tests', () {
    test(
      'Correctly deserializes PostgreSQL JSON with integer ID and string dates',
      () {
        final json = {
          'id': 42,
          'user_id': 1,
          'food_name': 'Organic Milk',
          'category': 'Dairy',
          'quantity': 2,
          'purchase_date': '2026-09-01',
          'expiry_date': '2026-09-08',
          'storage_location': 'Refrigerator',
          'status': 'active',
          'notes': 'Whole milk',
          'created_at': '2026-09-01T08:30:00.123Z',
          'updated_at': '2026-09-01T09:45:00.456Z',
        };

        final item = FoodItem.fromJson(json);

        expect(item.id, 42);
        expect(item.userId, 1);
        expect(item.foodName, 'Organic Milk');
        expect(item.category, 'Dairy');
        expect(item.quantity, 2);
        expect(item.purchaseDate, DateTime(2026, 9, 1));
        expect(item.expiryDate, DateTime(2026, 9, 8));
        expect(item.storageLocation, 'Refrigerator');
        expect(item.status, 'active');
        expect(item.notes, 'Whole milk');
        expect(
          item.createdAt,
          DateTime.parse('2026-09-01T08:30:00.123Z').toLocal(),
        );
        expect(
          item.updatedAt,
          DateTime.parse('2026-09-01T09:45:00.456Z').toLocal(),
        );
      },
    );

    test('Correctly handles string IDs and nullable purchase_date/notes', () {
      final json = {
        'id': '99',
        'userId': '5',
        'foodName': 'Fresh Spinach',
        'category': null,
        'quantity': '3',
        'purchase_date': null,
        'expiry_date': '2026-09-05',
        'storage_location': null,
        'status': 'ACTIVE',
        'notes': null,
        'created_at': '2026-09-01T10:00:00.000Z',
        'updated_at': '2026-09-01T10:00:00.000Z',
      };

      final item = FoodItem.fromJson(json);

      expect(item.id, 99);
      expect(item.userId, 5);
      expect(item.foodName, 'Fresh Spinach');
      expect(item.category, isNull);
      expect(item.quantity, 3);
      expect(item.purchaseDate, isNull);
      expect(item.expiryDate, DateTime(2026, 9, 5));
      expect(item.storageLocation, isNull);
      expect(item.status, 'active');
      expect(item.notes, isNull);
    });

    test(
      'toCreatePayload excludes id, user_id, status, created_at, updated_at',
      () {
        final item = FoodItem(
          id: 10,
          userId: 2,
          foodName: 'Greek Yogurt',
          category: 'Dairy',
          quantity: 4,
          purchaseDate: DateTime(2026, 9, 1),
          expiryDate: DateTime(2026, 9, 15),
          storageLocation: 'Fridge',
          status: 'active',
          notes: 'Vanilla flavor',
          createdAt: DateTime(2026, 9, 1, 12, 0),
          updatedAt: DateTime(2026, 9, 1, 12, 0),
        );

        final payload = item.toCreatePayload();

        expect(payload['food_name'], 'Greek Yogurt');
        expect(payload['category'], 'Dairy');
        expect(payload['quantity'], 4);
        expect(payload['purchase_date'], '2026-09-01');
        expect(payload['expiry_date'], '2026-09-15');
        expect(payload['storage_location'], 'Fridge');
        expect(payload['notes'], 'Vanilla flavor');

        expect(payload.containsKey('id'), isFalse);
        expect(payload.containsKey('user_id'), isFalse);
        expect(payload.containsKey('userId'), isFalse);
        expect(payload.containsKey('status'), isFalse);
        expect(payload.containsKey('created_at'), isFalse);
        expect(payload.containsKey('updated_at'), isFalse);
      },
    );

    test('toUpdatePayload allows nullable fields to be explicitly null', () {
      final item = FoodItem(
        id: 10,
        userId: 2,
        foodName: 'Bread',
        category: null,
        quantity: 1,
        purchaseDate: null,
        expiryDate: DateTime(2026, 9, 7),
        storageLocation: null,
        status: 'active',
        notes: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final payload = item.toUpdatePayload();

      expect(payload['food_name'], 'Bread');
      expect(payload['category'], isNull);
      expect(payload['quantity'], 1);
      expect(payload['purchase_date'], isNull);
      expect(payload['expiry_date'], '2026-09-07');
      expect(payload['storage_location'], isNull);
      expect(payload['notes'], isNull);

      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('user_id'), isFalse);
      expect(payload.containsKey('status'), isFalse);
      expect(payload.containsKey('created_at'), isFalse);
      expect(payload.containsKey('updated_at'), isFalse);
    });

    test(
      'Expiry state and days until expiry calculate correctly from local midnight',
      () {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        // Expired item (yesterday)
        final expiredItem = FoodItem(
          id: 1,
          userId: 1,
          foodName: 'Expired Food',
          expiryDate: today.subtract(const Duration(days: 1)),
          createdAt: now,
          updatedAt: now,
        );
        expect(expiredItem.daysUntilExpiry, -1);
        expect(expiredItem.expiryState, FoodExpiryState.expired);
        expect(expiredItem.isExpired, isTrue);
        expect(expiredItem.expiryStatusDisplay, 'Expired yesterday');

        // Expires today
        final todayItem = FoodItem(
          id: 2,
          userId: 1,
          foodName: 'Today Food',
          expiryDate: today,
          createdAt: now,
          updatedAt: now,
        );
        expect(todayItem.daysUntilExpiry, 0);
        expect(todayItem.expiryState, FoodExpiryState.expiresToday);
        expect(todayItem.isExpiringToday, isTrue);
        expect(todayItem.expiryStatusDisplay, 'Expires today');

        // Expiring soon (2 days left)
        final soonItem = FoodItem(
          id: 3,
          userId: 1,
          foodName: 'Soon Food',
          expiryDate: today.add(const Duration(days: 2)),
          createdAt: now,
          updatedAt: now,
        );
        expect(soonItem.daysUntilExpiry, 2);
        expect(soonItem.expiryState, FoodExpiryState.expiringSoon);
        expect(soonItem.isExpiringSoon, isTrue);
        expect(soonItem.expiryStatusDisplay, 'Expires in 2 days');

        // Fresh (7 days left)
        final freshItem = FoodItem(
          id: 4,
          userId: 1,
          foodName: 'Fresh Food',
          expiryDate: today.add(const Duration(days: 7)),
          createdAt: now,
          updatedAt: now,
        );
        expect(freshItem.daysUntilExpiry, 7);
        expect(freshItem.expiryState, FoodExpiryState.fresh);
        expect(freshItem.isFresh, isTrue);
        expect(freshItem.expiryStatusDisplay, 'Fresh (7 days left)');

        // Consumed item
        final consumedItem = FoodItem(
          id: 5,
          userId: 1,
          foodName: 'Consumed Food',
          status: 'consumed',
          expiryDate: today.add(const Duration(days: 7)),
          createdAt: now,
          updatedAt: now,
        );
        expect(consumedItem.expiryStatusDisplay, 'Consumed');
      },
    );
  });
}
