import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../food/providers/food_providers.dart';
import '../../notifications/providers/notification_providers.dart';

/// Epoch state provider that increments on every session change.
/// Any asynchronous network call checks this epoch to discard late responses
/// belonging to an earlier or logged-out session.
final authSessionEpochProvider = StateProvider<int>((ref) => 0);

/// Centralized session controller that manages account switching, logout,
/// and token expiration cleanup across all Riverpod providers.
///
/// NOTE: AuthRepository does NOT depend on this controller (zero circular dependency).
/// When repositories catch 401, they throw AuthException('...', '401').
class AuthSessionController extends StateNotifier<int> {
  final Ref _ref;

  AuthSessionController(this._ref) : super(0);

  /// Centralized atomic cleanup of all user-specific state and providers.
  void _performComprehensiveCleanup() {
    // 1. Advance session epoch to discard any late in-flight HTTP responses
    state = state + 1;
    _ref.read(authSessionEpochProvider.notifier).state = state;

    // 2. Invalidate user profile
    _ref.invalidate(userProfileProvider);

    // 3. Invalidate all food inventory and statistics providers
    _ref.invalidate(allFoodItemsProvider);
    _ref.invalidate(filteredFoodItemsProvider);
    _ref.invalidate(foodStatsProvider);
    _ref.invalidate(useFirstFoodItemsProvider);

    // 4. Reset food UI filter state
    _ref.read(foodFilterProvider.notifier).reset();

    // 5. Invalidate notification providers and reset badge count
    _ref.invalidate(notificationsProvider);
    _ref.read(unreadNotificationCountProvider.notifier).reset();
    _ref.invalidate(unreadNotificationCountProvider);
    _ref.invalidate(notificationPreferencesProvider);

    // 6. Invalidate foreground notification coordinator
    _ref.invalidate(foregroundNotificationCoordinatorProvider);
  }

  /// User-initiated sign out.
  Future<void> signOut() async {
    final repo = _ref.read(authRepositoryProvider);
    await repo.signOut();
    _performComprehensiveCleanup();
  }

  /// Called when a 401 Unauthorized status is received from the backend.
  Future<void> expireSession() async {
    final repo = _ref.read(authRepositoryProvider);
    await repo.signOut();
    _performComprehensiveCleanup();
  }

  /// Called immediately when a new user successfully logs in to ensure a fresh session.
  void onSessionStarted() {
    _performComprehensiveCleanup();
  }
}

final authSessionControllerProvider =
    StateNotifierProvider<AuthSessionController, int>((ref) {
      return AuthSessionController(ref);
    });
