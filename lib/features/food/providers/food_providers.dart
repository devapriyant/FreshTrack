import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/controllers/auth_session_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../data/food_repository.dart';
import '../models/food_item.dart';

// Food Repository Provider
final foodRepositoryProvider = Provider<FoodRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final coordinator = ref.watch(sessionExpiryCoordinatorProvider);
  final repo = NodeFoodRepository(
    authRepository: authRepo,
    sessionExpiryCoordinator: coordinator,
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});

// UI Filter State Model
class FoodFilterState {
  final ExpiryFilter filter;
  final String? category;
  final String? storageLocation;
  final String searchQuery;

  const FoodFilterState({
    this.filter = ExpiryFilter.all,
    this.category,
    this.storageLocation,
    this.searchQuery = '',
  });

  FoodFilterState copyWith({
    ExpiryFilter? filter,
    String? category,
    bool clearCategory = false,
    String? storageLocation,
    bool clearStorageLocation = false,
    String? searchQuery,
  }) {
    return FoodFilterState(
      filter: filter ?? this.filter,
      category: clearCategory ? null : (category ?? this.category),
      storageLocation: clearStorageLocation
          ? null
          : (storageLocation ?? this.storageLocation),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// UI Filter State Notifier
class FoodFilterNotifier extends StateNotifier<FoodFilterState> {
  FoodFilterNotifier() : super(const FoodFilterState());

  void setFilter(ExpiryFilter filter) => state = state.copyWith(filter: filter);
  void setCategory(String? category) => state = state.copyWith(
    category: category,
    clearCategory: category == null,
  );
  void setStorageLocation(String? loc) => state = state.copyWith(
    storageLocation: loc,
    clearStorageLocation: loc == null,
  );
  void setSearchQuery(String query) =>
      state = state.copyWith(searchQuery: query);
  void reset() => state = const FoodFilterState();
}

final foodFilterProvider =
    StateNotifierProvider<FoodFilterNotifier, FoodFilterState>((ref) {
      final notifier = FoodFilterNotifier();
      ref.listen<int>(authSessionEpochProvider, (previous, next) {
        notifier.reset();
      });
      return notifier;
    });

// Complete Food Inventory Notifier bound to active user profile and session epoch
class AllFoodItemsNotifier extends AsyncNotifier<List<FoodItem>> {
  @override
  Future<List<FoodItem>> build() async {
    // 1. Explicitly bind to active user profile and session epoch
    final sessionEpoch = ref.watch(authSessionEpochProvider);
    final profile = await ref.watch(userProfileProvider.future);

    // Immediately return empty list if unauthenticated (never leak prior user's items)
    if (profile == null) {
      return const [];
    }

    final repo = ref.watch(foodRepositoryProvider);
    final currentEpoch = sessionEpoch;
    final items = await repo.getFoods();

    // 2. Session Epoch Guard: discard response if user session changed while request was in-flight
    if (ref.read(authSessionEpochProvider) != currentEpoch) {
      return const [];
    }

    return items;
  }

  Future<void> refresh() async {
    final profile = await ref.read(userProfileProvider.future);
    if (profile == null) {
      state = const AsyncValue.data([]);
      return;
    }

    final currentEpoch = ref.read(authSessionEpochProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(foodRepositoryProvider);
      final items = await repo.getFoods();
      if (ref.read(authSessionEpochProvider) != currentEpoch) {
        return <FoodItem>[];
      }
      return items;
    });
  }

  Future<FoodItem> addItem(Map<String, dynamic> payload) async {
    final repo = ref.read(foodRepositoryProvider);
    final newItem = await repo.addFood(payload);
    await refresh();
    return newItem;
  }

  Future<FoodItem> updateItem(int id, Map<String, dynamic> payload) async {
    final repo = ref.read(foodRepositoryProvider);
    final updated = await repo.updateFood(id, payload);
    await refresh();
    return updated;
  }

  Future<FoodItem> updateStatus(int id, String status) async {
    final repo = ref.read(foodRepositoryProvider);
    final updated = await repo.updateStatus(id, status);
    await refresh();
    return updated;
  }

  Future<void> deleteItem(int id) async {
    final repo = ref.read(foodRepositoryProvider);
    await repo.deleteFood(id);
    await refresh();
  }
}

final allFoodItemsProvider =
    AsyncNotifierProvider<AllFoodItemsNotifier, List<FoodItem>>(() {
      return AllFoodItemsNotifier();
    });

// Filtered Food Items Provider (Client-side filtering derived from allFoodItemsProvider)
final filteredFoodItemsProvider = Provider<AsyncValue<List<FoodItem>>>((ref) {
  final allItemsAsync = ref.watch(allFoodItemsProvider);
  final filterState = ref.watch(foodFilterProvider);

  return allItemsAsync.whenData((items) {
    return items.where((item) {
      // 1. Search filter
      if (filterState.searchQuery.trim().isNotEmpty) {
        final query = filterState.searchQuery.trim().toLowerCase();
        final nameMatch = item.foodName.toLowerCase().contains(query);
        final catMatch = item.category?.toLowerCase().contains(query) ?? false;
        final notesMatch = item.notes?.toLowerCase().contains(query) ?? false;
        if (!nameMatch && !catMatch && !notesMatch) return false;
      }

      // 2. Category filter
      if (filterState.category != null && filterState.category!.isNotEmpty) {
        if (item.category?.toLowerCase() !=
            filterState.category!.toLowerCase()) {
          return false;
        }
      }

      // 3. Storage Location filter
      if (filterState.storageLocation != null &&
          filterState.storageLocation!.isNotEmpty) {
        if (item.storageLocation?.toLowerCase() !=
            filterState.storageLocation!.toLowerCase()) {
          return false;
        }
      }

      // 4. Expiry/Lifecycle Filter
      switch (filterState.filter) {
        case ExpiryFilter.all:
          return true;
        case ExpiryFilter.active:
          return item.isActive;
        case ExpiryFilter.fresh:
          return item.isActive && item.expiryState == FoodExpiryState.fresh;
        case ExpiryFilter.expiringSoon:
          return item.isActive &&
              item.expiryState == FoodExpiryState.expiringSoon;
        case ExpiryFilter.expiresToday:
          return item.isActive &&
              item.expiryState == FoodExpiryState.expiresToday;
        case ExpiryFilter.expired:
          return item.isActive && item.expiryState == FoodExpiryState.expired;
        case ExpiryFilter.consumed:
          return item.isConsumed;
        case ExpiryFilter.discarded:
          return item.isDiscarded;
      }
    }).toList();
  });
});

// Summary Statistics Model
class FoodStats {
  final int totalCount;
  final int activeCount;
  final int freshCount;
  final int expiringSoonCount;
  final int expiresTodayCount;
  final int expiredCount;
  final int consumedCount;
  final int discardedCount;

  const FoodStats({
    this.totalCount = 0,
    this.activeCount = 0,
    this.freshCount = 0,
    this.expiringSoonCount = 0,
    this.expiresTodayCount = 0,
    this.expiredCount = 0,
    this.consumedCount = 0,
    this.discardedCount = 0,
  });
}

// Food Stats Provider (Derived strictly from allFoodItemsProvider)
final foodStatsProvider = Provider<FoodStats>((ref) {
  final allItemsAsync = ref.watch(allFoodItemsProvider);
  final items = allItemsAsync.value ?? [];

  int active = 0;
  int fresh = 0;
  int expiringSoon = 0;
  int expiresToday = 0;
  int expired = 0;
  int consumed = 0;
  int discarded = 0;

  for (final item in items) {
    if (item.isActive) {
      active++;
      switch (item.expiryState) {
        case FoodExpiryState.fresh:
          fresh++;
          break;
        case FoodExpiryState.expiringSoon:
          expiringSoon++;
          break;
        case FoodExpiryState.expiresToday:
          expiresToday++;
          break;
        case FoodExpiryState.expired:
          expired++;
          break;
      }
    } else if (item.isConsumed) {
      consumed++;
    } else if (item.isDiscarded) {
      discarded++;
    }
  }

  return FoodStats(
    totalCount: items.length,
    activeCount: active,
    freshCount: fresh,
    expiringSoonCount: expiringSoon,
    expiresTodayCount: expiresToday,
    expiredCount: expired,
    consumedCount: consumed,
    discardedCount: discarded,
  );
});

// Use First Food Items Provider (Derived strictly from allFoodItemsProvider)
final useFirstFoodItemsProvider = Provider<List<FoodItem>>((ref) {
  final allItemsAsync = ref.watch(allFoodItemsProvider);
  final items = allItemsAsync.value ?? [];

  final expiringItems = items
      .where(
        (item) =>
            item.isActive &&
            (item.expiryState == FoodExpiryState.expiresToday ||
                item.expiryState == FoodExpiryState.expiringSoon),
      )
      .toList();

  // Sort with nearest expiry date first
  expiringItems.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
  return expiringItems;
});
