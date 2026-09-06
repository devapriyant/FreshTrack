import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/controllers/auth_session_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../data/notification_repository.dart';
import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../services/browser_notification_service.dart';

// Notification Repository Provider
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final coordinator = ref.watch(sessionExpiryCoordinatorProvider);
  final repo = NodeNotificationRepository(
    authRepository: authRepo,
    sessionExpiryCoordinator: coordinator,
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});

// Browser Notification Service Provider
final browserNotificationServiceProvider = Provider<BrowserNotificationService>(
  (ref) {
    return BrowserNotificationService();
  },
);

// Notification Filter Enum & Provider
enum NotificationFilter { all, unread, expiringSoon, today, expired }

final notificationFilterProvider = StateProvider<NotificationFilter>((ref) {
  return NotificationFilter.all;
});

// Unread Notification Count Notifier
class UnreadNotificationCountNotifier extends StateNotifier<int> {
  UnreadNotificationCountNotifier() : super(0);

  void setCount(int count) => state = count;

  void decrement() {
    if (state > 0) state = state - 1;
  }

  void reset() => state = 0;
}

final unreadNotificationCountProvider =
    StateNotifierProvider<UnreadNotificationCountNotifier, int>((ref) {
      final notifier = UnreadNotificationCountNotifier();
      ref.listen<int>(authSessionEpochProvider, (previous, next) {
        notifier.reset();
      });
      return notifier;
    });

// Notifications List Notifier (Loads all notifications)
class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final sessionEpoch = ref.watch(authSessionEpochProvider);
    final profile = await ref.watch(userProfileProvider.future);

    // Return empty list immediately if unauthenticated
    if (profile == null) {
      ref.read(unreadNotificationCountProvider.notifier).reset();
      return const [];
    }

    final repo = ref.watch(notificationRepositoryProvider);
    final currentEpoch = sessionEpoch;
    final items = await repo.getNotifications();

    // Discard late response if session epoch advanced during fetch
    if (ref.read(authSessionEpochProvider) != currentEpoch) {
      return const [];
    }

    // Synchronize unread badge with fetched notifications
    final unread = items.where((n) => !n.isRead).length;
    ref.read(unreadNotificationCountProvider.notifier).setCount(unread);
    return items;
  }

  Future<void> refresh() async {
    final profile = await ref.read(userProfileProvider.future);
    if (profile == null) {
      state = const AsyncValue.data([]);
      ref.read(unreadNotificationCountProvider.notifier).reset();
      return;
    }

    final currentEpoch = ref.read(authSessionEpochProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notificationRepositoryProvider);
      final items = await repo.getNotifications();
      if (ref.read(authSessionEpochProvider) != currentEpoch) {
        return <AppNotification>[];
      }
      final unread = items.where((n) => !n.isRead).length;
      ref.read(unreadNotificationCountProvider.notifier).setCount(unread);
      return items;
    });
  }

  Future<void> markAsRead(int id) async {
    final currentList = state.value ?? [];
    // Optimistic update
    state = AsyncValue.data(
      currentList.map((n) {
        if (n.id == id && !n.isRead) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList(),
    );
    ref.read(unreadNotificationCountProvider.notifier).decrement();

    try {
      final repo = ref.read(notificationRepositoryProvider);
      await repo.markAsRead(id);
    } catch (e) {
      // Rollback on error
      await refresh();
      rethrow;
    }
  }

  Future<void> markAllAsRead() async {
    final currentList = state.value ?? [];
    // Optimistic update
    state = AsyncValue.data(
      currentList.map((n) => n.copyWith(isRead: true)).toList(),
    );
    ref.read(unreadNotificationCountProvider.notifier).reset();

    try {
      final repo = ref.read(notificationRepositoryProvider);
      await repo.markAllAsRead();
    } catch (e) {
      // Rollback on error
      await refresh();
      rethrow;
    }
  }

  Future<void> deleteNotification(int id) async {
    final currentList = state.value ?? [];
    final target = currentList.firstWhere(
      (n) => n.id == id,
      orElse: () => currentList.first,
    );
    final wasUnread = target.id == id && !target.isRead;

    // Optimistic update
    state = AsyncValue.data(currentList.where((n) => n.id != id).toList());
    if (wasUnread) {
      ref.read(unreadNotificationCountProvider.notifier).decrement();
    }

    try {
      final repo = ref.read(notificationRepositoryProvider);
      await repo.deleteNotification(id);
    } catch (e) {
      // Rollback on error
      await refresh();
      rethrow;
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(() {
      return NotificationsNotifier();
    });

// Filtered Notifications Provider
final filteredNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final notifsAsync = ref.watch(notificationsProvider);
  final filter = ref.watch(notificationFilterProvider);

  return notifsAsync.maybeWhen(
    data: (list) {
      switch (filter) {
        case NotificationFilter.all:
          return list;
        case NotificationFilter.unread:
          return list.where((n) => !n.isRead).toList();
        case NotificationFilter.expiringSoon:
          return list.where((n) => n.isExpiringSoon).toList();
        case NotificationFilter.today:
          return list.where((n) => n.isExpiresToday).toList();
        case NotificationFilter.expired:
          return list.where((n) => n.isExpired).toList();
      }
    },
    orElse: () => const [],
  );
});

// Notification Preferences Notifier
class NotificationPreferencesNotifier
    extends AsyncNotifier<NotificationPreferences> {
  @override
  Future<NotificationPreferences> build() async {
    final sessionEpoch = ref.watch(authSessionEpochProvider);
    final profile = await ref.watch(userProfileProvider.future);

    if (profile == null) {
      return const NotificationPreferences();
    }

    final repo = ref.watch(notificationRepositoryProvider);
    final currentEpoch = sessionEpoch;
    final prefs = await repo.getPreferences();

    if (ref.read(authSessionEpochProvider) != currentEpoch) {
      return const NotificationPreferences();
    }

    return prefs;
  }

  Future<void> refresh() async {
    final profile = await ref.read(userProfileProvider.future);
    if (profile == null) {
      state = const AsyncValue.data(NotificationPreferences());
      return;
    }

    final currentEpoch = ref.read(authSessionEpochProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(notificationRepositoryProvider);
      final prefs = await repo.getPreferences();
      if (ref.read(authSessionEpochProvider) != currentEpoch) {
        return const NotificationPreferences();
      }
      return prefs;
    });
  }

  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences prefs,
  ) async {
    final repo = ref.read(notificationRepositoryProvider);
    final updated = await repo.updatePreferences(prefs);
    state = AsyncValue.data(updated);
    return updated;
  }
}

final notificationPreferencesProvider =
    AsyncNotifierProvider<
      NotificationPreferencesNotifier,
      NotificationPreferences
    >(() {
      return NotificationPreferencesNotifier();
    });

// Test override flag to disable coordinator during widget tests
final enableForegroundCoordinatorProvider = StateProvider<bool>((ref) => true);

// Foreground Notification Coordinator
class ForegroundNotificationCoordinator with WidgetsBindingObserver {
  final T Function<T>(ProviderListenable<T>) reader;
  Timer? _timer;
  bool _isPolling = false;
  final Set<int> _alertedNotificationIds = {};
  bool _isDisposed = false;

  static bool enableInTest = false;

  ForegroundNotificationCoordinator({
    required this.reader,
    bool autoStart = true,
  }) {
    WidgetsBinding? binding;
    try {
      binding = WidgetsBinding.instance;
    } catch (_) {
      binding = null;
    }

    final isTestEnvironment =
        binding != null && binding.runtimeType.toString().contains('Test');
    if (autoStart && (!isTestEnvironment || enableInTest)) {
      start();
    }
  }

  factory ForegroundNotificationCoordinator.fromRef(
    Ref ref, {
    bool autoStart = true,
  }) {
    return ForegroundNotificationCoordinator(
      reader: ref.read,
      autoStart: autoStart,
    );
  }

  void start() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    poll();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      poll();
    }
  }

  Future<void> poll() async {
    if (_isPolling || _isDisposed) return;
    _isPolling = true;

    try {
      final repo = reader(notificationRepositoryProvider);
      final count = await repo.getUnreadCount();
      reader(unreadNotificationCountProvider.notifier).setCount(count);

      // Check browser notification delivery
      final browserService = reader(browserNotificationServiceProvider);
      final prefsAsync = reader(notificationPreferencesProvider);
      var prefs = prefsAsync.value;
      if (prefs == null && prefsAsync.isLoading) {
        try {
          prefs = await reader(notificationPreferencesProvider.future);
        } catch (_) {}
      }

      if (prefs != null &&
          prefs.browserNotificationsEnabled &&
          browserService.isSupported) {
        final hasPerm = await browserService.hasPermission();
        if (hasPerm) {
          final unreadList = await repo.getNotifications(
            unread: true,
            limit: 10,
          );
          for (final notif in unreadList) {
            if (!_alertedNotificationIds.contains(notif.id)) {
              _alertedNotificationIds.add(notif.id);
              browserService.showNotification(
                id: notif.id,
                title: notif.title,
                body: notif.message,
              );
            }
          }
        }
      }
    } catch (_) {
      // Safe error boundary
    } finally {
      _isPolling = false;
    }
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }
}

final foregroundNotificationCoordinatorProvider =
    Provider<ForegroundNotificationCoordinator?>((ref) {
      final isEnabled = ref.watch(enableForegroundCoordinatorProvider);
      if (!isEnabled) return null;

      final authStateAsync = ref.watch(authStateProvider);
      final isAuthenticated = authStateAsync.value ?? false;

      if (!isAuthenticated) return null;

      final coordinator = ForegroundNotificationCoordinator.fromRef(ref);
      ref.onDispose(() => coordinator.dispose());
      return coordinator;
    });
