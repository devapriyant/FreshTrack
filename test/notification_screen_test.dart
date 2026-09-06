import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/notifications/data/notification_repository.dart';
import 'package:freshtrack/features/notifications/models/app_notification.dart';
import 'package:freshtrack/features/notifications/models/notification_preferences.dart';
import 'package:freshtrack/features/notifications/providers/notification_providers.dart';
import 'package:freshtrack/features/notifications/screens/notification_screen.dart';
import 'package:freshtrack/features/notifications/screens/notification_settings_screen.dart';

class MockNotificationRepository implements NotificationRepository {
  List<AppNotification> items;
  NotificationPreferences prefs;

  MockNotificationRepository({
    this.items = const [],
    this.prefs = const NotificationPreferences(),
  });

  @override
  Future<List<AppNotification>> getNotifications({
    bool? unread,
    String? type,
    int limit = 30,
    int offset = 0,
  }) async {
    return items;
  }

  @override
  Future<int> getUnreadCount() async {
    return items.where((n) => !n.isRead).length;
  }

  @override
  Future<AppNotification> markAsRead(int id) async => items.first;

  @override
  Future<int> markAllAsRead() async => 0;

  @override
  Future<void> deleteNotification(int id) async {}

  @override
  Future<NotificationPreferences> getPreferences() async => prefs;

  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences preferences,
  ) async {
    prefs = preferences;
    return prefs;
  }

  @override
  void dispose() {}
}

void main() {
  group('NotificationScreen Widget Tests', () {
    testWidgets('Displays empty state when notification list is empty', (
      WidgetTester tester,
    ) async {
      final mockRepo = MockNotificationRepository(items: []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(mockRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: NotificationScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Expiring Soon'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('No Notifications Yet'), findsOneWidget);
    });

    testWidgets('Renders notification cards with title and expiry info', (
      WidgetTester tester,
    ) async {
      final mockRepo = MockNotificationRepository(
        items: [
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
        ],
      );

      final mockUser = UserProfile(
        id: '1',
        userId: '1',
        fullName: 'Test User',
        email: 'test@example.com',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) async => mockUser),
            notificationRepositoryProvider.overrideWithValue(mockRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: NotificationScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Milk Expiring Soon'), findsOneWidget);
      expect(find.text('Milk expires in 3 days.'), findsOneWidget);
      expect(find.text('Expiry: 2026-09-08'), findsOneWidget);
    });
  });

  group('NotificationSettingsScreen Widget Tests', () {
    testWidgets('Renders controls, offsets, hour, timezone, and save button', (
      WidgetTester tester,
    ) async {
      final mockRepo = MockNotificationRepository(
        prefs: const NotificationPreferences(
          notificationsEnabled: true,
          browserNotificationsEnabled: false,
          reminderDays: [7, 3, 1, 0],
          timezone: 'Asia/Kolkata',
          reminderHour: 9,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(mockRepo),
            enableForegroundCoordinatorProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: NotificationSettingsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.text('Enable Expiry Reminders'), findsOneWidget);
      expect(find.text('7 days before expiry'), findsOneWidget);
      expect(find.text('3 days before expiry'), findsOneWidget);
      expect(find.text('1 day before (tomorrow)'), findsOneWidget);
      expect(find.text('On expiry day (today)'), findsOneWidget);
      expect(find.text('Daily Reminder Hour'), findsOneWidget);
      expect(find.text('Timezone'), findsOneWidget);
      expect(find.text('Foreground Browser Notifications'), findsOneWidget);
      expect(find.text('Save Settings'), findsOneWidget);
    });
  });
}
