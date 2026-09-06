import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshtrack/features/auth/controllers/auth_session_controller.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/notifications/data/notification_repository.dart';
import 'package:freshtrack/features/notifications/models/app_notification.dart';
import 'package:freshtrack/features/notifications/models/notification_preferences.dart';
import 'package:freshtrack/features/notifications/providers/notification_providers.dart';
import 'package:freshtrack/features/notifications/services/browser_notification_service.dart';

class FakeNotificationRepository implements NotificationRepository {
  List<AppNotification> items = [
    AppNotification(
      id: 1,
      foodItemId: 10,
      type: 'expiring_soon',
      title: 'Milk Expiring Soon',
      message: 'Milk expires in 3 days.',
      isRead: false,
      expiryDate: DateTime(2026, 9, 8),
      createdAt: DateTime(2026, 9, 5),
    ),
    AppNotification(
      id: 2,
      foodItemId: 11,
      type: 'expires_today',
      title: 'Eggs Expires Today',
      message: 'Eggs expire today.',
      isRead: false,
      expiryDate: DateTime(2026, 9, 2),
      createdAt: DateTime(2026, 9, 2),
    ),
    AppNotification(
      id: 3,
      foodItemId: 12,
      type: 'expired',
      title: 'Yogurt Expired',
      message: 'Yogurt has expired.',
      isRead: true,
      expiryDate: DateTime(2026, 8, 30),
      createdAt: DateTime(2026, 9, 1),
    ),
  ];

  NotificationPreferences prefs = const NotificationPreferences(
    notificationsEnabled: true,
    browserNotificationsEnabled: false,
    reminderDays: [7, 3, 1, 0],
    timezone: 'Asia/Kolkata',
    reminderHour: 9,
  );

  Completer<List<AppNotification>>? delayedCompleter;
  int getNotificationsCallCount = 0;

  @override
  Future<List<AppNotification>> getNotifications({
    bool? unread,
    String? type,
    int limit = 30,
    int offset = 0,
  }) async {
    getNotificationsCallCount++;
    if (delayedCompleter != null) {
      return await delayedCompleter!.future;
    }
    var result = List<AppNotification>.from(items);
    if (unread == true) {
      result = result.where((n) => !n.isRead).toList();
    }
    if (type != null) {
      result = result.where((n) => n.type == type).toList();
    }
    return result;
  }

  @override
  Future<int> getUnreadCount() async {
    return items.where((n) => !n.isRead).length;
  }

  @override
  Future<AppNotification> markAsRead(int id) async {
    final index = items.indexWhere((n) => n.id == id);
    if (index != -1) {
      items[index] = items[index].copyWith(isRead: true);
      return items[index];
    }
    throw Exception('Not found');
  }

  @override
  Future<int> markAllAsRead() async {
    int count = 0;
    for (int i = 0; i < items.length; i++) {
      if (!items[i].isRead) {
        items[i] = items[i].copyWith(isRead: true);
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> deleteNotification(int id) async {
    items.removeWhere((n) => n.id == id);
  }

  @override
  Future<NotificationPreferences> getPreferences() async => prefs;

  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences newPrefs,
  ) async {
    prefs = newPrefs;
    return prefs;
  }

  @override
  void dispose() {}
}

class FakeAuthRepository implements AuthRepository {
  @override
  Future<void> signOut() async {}

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<UserProfile?> getCurrentProfile() async => null;

  @override
  Future<String?> getToken() async => 'test_token';

  @override
  Future<bool> get isAuthenticated async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBrowserNotificationService implements BrowserNotificationService {
  final List<int> shownNotificationIds = [];
  bool permissionGranted = true;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  void showNotification({
    required int id,
    required String title,
    required String body,
  }) {
    shownNotificationIds.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Providers Tests', () {
    late FakeNotificationRepository fakeRepo;
    late FakeBrowserNotificationService fakeBrowser;

    final testProfile = UserProfile(
      id: '1',
      userId: '1',
      fullName: 'Test User',
      email: 'test@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setUp(() {
      fakeRepo = FakeNotificationRepository();
      fakeBrowser = FakeBrowserNotificationService();
    });

    test(
      'notificationsProvider loads list and synchronizes unread count when authenticated',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        final list = await container.read(notificationsProvider.future);
        expect(list.length, 3);

        final unreadBadge = container.read(unreadNotificationCountProvider);
        expect(unreadBadge, 2);
      },
    );

    test(
      'markAsRead optimistically updates state and decrements badge',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        await container.read(notificationsProvider.future);
        expect(container.read(unreadNotificationCountProvider), 2);

        await container.read(notificationsProvider.notifier).markAsRead(1);

        final updatedList = container.read(notificationsProvider).value!;
        expect(updatedList.firstWhere((n) => n.id == 1).isRead, true);
        expect(container.read(unreadNotificationCountProvider), 1);
      },
    );

    test(
      'markAllAsRead sets all isRead=true and resets unread count to 0',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        await container.read(notificationsProvider.future);
        expect(container.read(unreadNotificationCountProvider), 2);

        await container.read(notificationsProvider.notifier).markAllAsRead();

        final updatedList = container.read(notificationsProvider).value!;
        expect(updatedList.every((n) => n.isRead), true);
        expect(container.read(unreadNotificationCountProvider), 0);
      },
    );

    test(
      'deleteNotification removes item from state and decrements if unread',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        await container.read(notificationsProvider.future);
        expect(container.read(unreadNotificationCountProvider), 2);

        await container
            .read(notificationsProvider.notifier)
            .deleteNotification(1);

        final updatedList = container.read(notificationsProvider).value!;
        expect(updatedList.length, 2);
        expect(updatedList.any((n) => n.id == 1), false);
        expect(container.read(unreadNotificationCountProvider), 1);
      },
    );

    test(
      'filteredNotificationsProvider filters by unread, today, and expired',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        await container.read(notificationsProvider.future);

        container.read(notificationFilterProvider.notifier).state =
            NotificationFilter.unread;
        final unreadList = container.read(filteredNotificationsProvider);
        expect(unreadList.length, 2);

        container.read(notificationFilterProvider.notifier).state =
            NotificationFilter.expired;
        final expiredList = container.read(filteredNotificationsProvider);
        expect(expiredList.length, 1);
        expect(expiredList.first.id, 3);
      },
    );

    test(
      'notificationPreferencesProvider loads and updates settings',
      () async {
        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        final initial = await container.read(
          notificationPreferencesProvider.future,
        );
        expect(initial.timezone, 'Asia/Kolkata');

        const newSettings = NotificationPreferences(
          notificationsEnabled: true,
          browserNotificationsEnabled: true,
          reminderDays: [3, 1],
          timezone: 'UTC',
          reminderHour: 10,
        );

        final updated = await container
            .read(notificationPreferencesProvider.notifier)
            .updatePreferences(newSettings);

        expect(updated.timezone, 'UTC');
        expect(updated.browserNotificationsEnabled, true);
      },
    );

    test(
      'ForegroundNotificationCoordinator deduplicates alerts by notification ID',
      () async {
        fakeRepo.prefs = fakeRepo.prefs.copyWith(
          browserNotificationsEnabled: true,
        );

        final container = ProviderContainer(
          overrides: [
            userProfileProvider.overrideWith((ref) async => testProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            browserNotificationServiceProvider.overrideWithValue(fakeBrowser),
            authStateProvider.overrideWith((ref) => Stream.value(true)),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        final coordinator = ForegroundNotificationCoordinator(
          reader: container.read,
          autoStart: false,
        );
        addTearDown(coordinator.dispose);

        await coordinator.poll();
        expect(fakeBrowser.shownNotificationIds.length, 2);
        expect(fakeBrowser.shownNotificationIds.contains(1), true);
        expect(fakeBrowser.shownNotificationIds.contains(2), true);

        await coordinator.poll();
        expect(fakeBrowser.shownNotificationIds.length, 2);
      },
    );

    // ============================================================
    // NEW HARDENED NOTIFICATION TESTS
    // ============================================================

    test(
      'Logged-out build returns empty list without making unauthorized requests',
      () async {
        final container = ProviderContainer(
          overrides: [
            // Explicitly unauthenticated (profile is null)
            userProfileProvider.overrideWith((ref) async => null),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        final list = await container.read(notificationsProvider.future);
        expect(list.isEmpty, isTrue);

        final unreadBadge = container.read(unreadNotificationCountProvider);
        expect(unreadBadge, 0);

        // Repository must NOT have been queried
        expect(fakeRepo.getNotificationsCallCount, 0);
      },
    );

    test(
      'Logout during in-flight notification request discards late response',
      () async {
        fakeRepo.delayedCompleter = Completer<List<AppNotification>>();
        UserProfile? activeProfile = testProfile;

        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            userProfileProvider.overrideWith((ref) async => activeProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        // 1. Start loading notifications
        container.read(notificationsProvider);

        // 2. User logs out while request is pending (epoch advances and profile clears)
        activeProfile = null;
        await container.read(authSessionControllerProvider.notifier).signOut();

        // 3. Complete the delayed request
        fakeRepo.delayedCompleter!.complete([
          AppNotification(
            id: 999,
            foodItemId: 1,
            type: 'expiring_soon',
            title: 'Late Stale Notification',
            message: 'Stale message',
            isRead: false,
            expiryDate: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        ]);

        final result = await container.read(notificationsProvider.future);
        // Discarded because session epoch advanced!
        expect(result.isEmpty, isTrue);
      },
    );

    test(
      'Rapid User A -> User B switching leaves zero User A notifications for User B',
      () async {
        var currentProfile = testProfile;

        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            userProfileProvider.overrideWith((ref) async => currentProfile),
            notificationRepositoryProvider.overrideWithValue(fakeRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
        );
        addTearDown(container.dispose);

        // User A loads notifications
        final userAList = await container.read(notificationsProvider.future);
        expect(userAList.length, 3);

        // User A logs out
        await container.read(authSessionControllerProvider.notifier).signOut();

        // Clear fakeRepo notifications for User B
        fakeRepo.items = [
          AppNotification(
            id: 100,
            foodItemId: 50,
            type: 'expiring_soon',
            title: 'User B Only Alert',
            message: 'Belongs to B',
            isRead: false,
            expiryDate: DateTime(2026, 9, 15),
            createdAt: DateTime.now(),
          ),
        ];

        // User B logs in
        currentProfile = UserProfile(
          id: '2',
          userId: '2',
          fullName: 'User B',
          email: 'userb@example.com',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        container
            .read(authSessionControllerProvider.notifier)
            .onSessionStarted();

        final userBList = await container.read(notificationsProvider.future);
        expect(userBList.length, 1);
        expect(userBList.first.title, 'User B Only Alert');
        expect(
          userBList.any((n) => n.id == 1 || n.id == 2 || n.id == 3),
          isFalse,
        );
      },
    );
  });
}
