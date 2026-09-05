import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/food/data/food_repository.dart';
import 'package:freshtrack/features/food/models/food_item.dart';
import 'package:freshtrack/features/food/providers/food_providers.dart';

class StubFoodRepository implements FoodRepository {
  List<FoodItem> items = [];

  @override
  Future<List<FoodItem>> getFoods({
    String? status,
    String? category,
    String? storageLocation,
    String? search,
  }) async {
    return items;
  }

  @override
  Future<FoodItem> addFood(Map<String, dynamic> payload) async {
    final newItem = FoodItem(
      id: items.length + 1,
      userId: 1,
      foodName: payload['food_name'] as String,
      category: payload['category'] as String?,
      quantity: payload['quantity'] as int? ?? 1,
      expiryDate: DateTime.parse(payload['expiry_date'] as String),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    items.add(newItem);
    return newItem;
  }

  @override
  Future<FoodItem> updateFood(int id, Map<String, dynamic> payload) async {
    final index = items.indexWhere((i) => i.id == id);
    final updated = items[index].copyWith(
      foodName: payload['food_name'] as String,
      quantity: payload['quantity'] as int?,
      expiryDate: DateTime.parse(payload['expiry_date'] as String),
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<FoodItem> updateStatus(int id, String status) async {
    final index = items.indexWhere((i) => i.id == id);
    final updated = items[index].copyWith(status: status);
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteFood(int id) async {
    items.removeWhere((i) => i.id == id);
  }

  @override
  Future<FoodItem> getFood(int id) async {
    return items.firstWhere((i) => i.id == id);
  }

  @override
  void dispose() {}
}

void main() {
  group('Food Providers Tests', () {
    late StubFoodRepository stubRepo;
    late ProviderContainer container;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setUp(() {
      stubRepo = StubFoodRepository();
      stubRepo.items = [
        FoodItem(
          id: 1,
          userId: 1,
          foodName: 'Fresh Milk',
          category: 'Dairy',
          quantity: 2,
          expiryDate: today.add(const Duration(days: 7)), // fresh
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
        FoodItem(
          id: 2,
          userId: 1,
          foodName: 'Avocado',
          category: 'Produce',
          quantity: 1,
          expiryDate: today, // expiresToday
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
        FoodItem(
          id: 3,
          userId: 1,
          foodName: 'Yogurt',
          category: 'Dairy',
          quantity: 1,
          expiryDate: today.add(const Duration(days: 2)), // expiringSoon
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
        FoodItem(
          id: 4,
          userId: 1,
          foodName: 'Old Bread',
          category: 'Bakery',
          quantity: 1,
          expiryDate: today.subtract(const Duration(days: 3)), // expired
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
        FoodItem(
          id: 5,
          userId: 1,
          foodName: 'Consumed Chicken',
          category: 'Meat',
          quantity: 1,
          expiryDate: today.add(const Duration(days: 1)),
          status: 'consumed',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      container = ProviderContainer(
        overrides: [
          foodRepositoryProvider.overrideWithValue(stubRepo),
          userProfileProvider.overrideWith((ref) => Future.value(
                UserProfile(
                  id: '1',
                  userId: '1',
                  fullName: 'Test User',
                  email: 'test@example.com',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              )),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'foodStatsProvider accurately computes active-only expiry stats and separates expiresToday',
      () async {
        // Trigger allFoodItemsProvider loading
        await container.read(allFoodItemsProvider.future);

        final stats = container.read(foodStatsProvider);

        expect(stats.totalCount, 5);
        expect(stats.activeCount, 4);
        expect(stats.freshCount, 1); // Fresh Milk
        expect(stats.expiresTodayCount, 1); // Avocado
        expect(stats.expiringSoonCount, 1); // Yogurt
        expect(stats.expiredCount, 1); // Old Bread
        expect(stats.consumedCount, 1); // Consumed Chicken
        expect(stats.discardedCount, 0);
      },
    );

    test(
      'useFirstFoodItemsProvider contains today and soon expiring items sorted nearest first',
      () async {
        await container.read(allFoodItemsProvider.future);

        final useFirst = container.read(useFirstFoodItemsProvider);

        expect(useFirst.length, 2);
        expect(useFirst[0].foodName, 'Avocado'); // 0 days (today)
        expect(useFirst[1].foodName, 'Yogurt'); // 2 days (soon)
      },
    );

    test(
      'filteredFoodItemsProvider filters in-memory by search, category, and ExpiryFilter',
      () async {
        await container.read(allFoodItemsProvider.future);

        // 1. Initial: all items
        var filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 5);

        // 2. Filter by search "milk"
        container.read(foodFilterProvider.notifier).setSearchQuery('milk');
        filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 1);
        expect(filtered.first.foodName, 'Fresh Milk');

        // 3. Clear search and filter by category "Dairy"
        container.read(foodFilterProvider.notifier).setSearchQuery('');
        container.read(foodFilterProvider.notifier).setCategory('Dairy');
        filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 2);

        // 4. Filter by ExpiryFilter.expiringSoon
        container.read(foodFilterProvider.notifier).setCategory(null);
        container
            .read(foodFilterProvider.notifier)
            .setFilter(ExpiryFilter.expiringSoon);
        filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 1);
        expect(filtered.first.foodName, 'Yogurt');

        // 5. Filter by ExpiryFilter.expiresToday
        container
            .read(foodFilterProvider.notifier)
            .setFilter(ExpiryFilter.expiresToday);
        filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 1);
        expect(filtered.first.foodName, 'Avocado');

        // 6. Filter by ExpiryFilter.consumed
        container
            .read(foodFilterProvider.notifier)
            .setFilter(ExpiryFilter.consumed);
        filtered = container.read(filteredFoodItemsProvider).value!;
        expect(filtered.length, 1);
        expect(filtered.first.foodName, 'Consumed Chicken');
      },
    );

    test(
      'allFoodItemsProvider mutations refresh the item list and stats',
      () async {
        await container.read(allFoodItemsProvider.future);

        // Add item
        await container.read(allFoodItemsProvider.notifier).addItem({
          'food_name': 'Bananas',
          'category': 'Produce',
          'quantity': 6,
          'expiry_date': today
              .add(const Duration(days: 5))
              .toIso8601String()
              .substring(0, 10),
        });

        var stats = container.read(foodStatsProvider);
        expect(stats.totalCount, 6);
        expect(stats.activeCount, 5);
        expect(stats.freshCount, 2);

        // Update status
        await container
            .read(allFoodItemsProvider.notifier)
            .updateStatus(1, 'consumed');
        stats = container.read(foodStatsProvider);
        expect(stats.activeCount, 4);
        expect(stats.consumedCount, 2);

        // Delete item
        await container.read(allFoodItemsProvider.notifier).deleteItem(4);
        stats = container.read(foodStatsProvider);
        expect(stats.totalCount, 5);
        expect(stats.expiredCount, 0);
      },
    );
  });
}
