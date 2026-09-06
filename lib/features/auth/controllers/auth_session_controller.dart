import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/session_expiry_coordinator.dart';
import '../data/auth_repository.dart';

/// Centralized session controller that manages account switching, logout,
/// and token expiration cleanup across Riverpod providers.
///
/// Implements [SessionExpiryCoordinator].
/// Does NOT import food or notification providers, maintaining a strictly
/// unidirectional dependency hierarchy.
class AuthSessionController extends StateNotifier<int>
    implements SessionExpiryCoordinator {
  final Ref _ref;
  bool _isExpiring = false;

  AuthSessionController(this._ref) : super(0);

  /// Centralized atomic cleanup of session credentials and profile.
  /// Advancing the integer state (epoch) notifies all watchers
  /// to discard prior data and re-evaluate for the unauthenticated state.
  void _performComprehensiveCleanup() {
    state = state + 1;
    _ref.invalidate(userProfileProvider);
  }

  /// User-initiated sign out.
  Future<void> signOut() async {
    final repo = _ref.read(authRepositoryProvider);
    await repo.signOut();
    _performComprehensiveCleanup();
  }

  /// Authoritative session expiry invoked on HTTP 401.
  /// Deduplicated so concurrent 401s advance the epoch exactly once.
  @override
  Future<void> expireSession() async {
    if (_isExpiring) return;
    _isExpiring = true;
    try {
      final repo = _ref.read(authRepositoryProvider);
      await repo.signOut();
      _performComprehensiveCleanup();
    } finally {
      _isExpiring = false;
    }
  }

  /// Called immediately when a new user successfully logs in to ensure a fresh session.
  void onSessionStarted() {
    _performComprehensiveCleanup();
  }
}

/// Authoritative session controller provider.
final authSessionControllerProvider =
    StateNotifierProvider<AuthSessionController, int>((ref) {
      return AuthSessionController(ref);
    });

/// Single source of truth for session epoch.
/// Derived directly from AuthSessionController's integer state.
final authSessionEpochProvider = Provider<int>((ref) {
  return ref.watch(authSessionControllerProvider);
});

/// Concrete, non-null SessionExpiryCoordinator provider defined in auth layer.
final sessionExpiryCoordinatorProvider = Provider<SessionExpiryCoordinator>((
  ref,
) {
  return ref.watch(authSessionControllerProvider.notifier);
});
