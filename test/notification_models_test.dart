import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/features/notifications/models/app_notification.dart';
import 'package:freshtrack/features/notifications/models/notification_preferences.dart';

void main() {
  group('AppNotification Model Tests', () {
    test(
      'Correctly deserializes PostgreSQL JSON with integer IDs and date-only normalization',
      () {
        final json = {
          'id': 101,
          'user_id': 10,
          'food_item_id': 42,
          'type': 'expiring_soon',
          'title': 'Milk Expiring Soon',
          'message': 'Milk expires in 3 days.',
          'is_read': false,
          'expiry_date': '2026-09-08',
          'created_at': '2026-09-05T08:30:15.123Z',
          'food_name': 'Milk',
          'category': 'Dairy',
          'quantity': 2,
          'storage_location': 'Fridge',
          'food_status': 'active',
        };

        final notif = AppNotification.fromJson(json);

        expect(notif.id, 101);
        expect(notif.foodItemId, 42);
        expect(notif.type, 'expiring_soon');
        expect(notif.title, 'Milk Expiring Soon');
        expect(notif.message, 'Milk expires in 3 days.');
        expect(notif.isRead, false);
        // Expiry date normalized to local date-only
        expect(notif.expiryDate, DateTime(2026, 9, 8));
        // Created at timestamp precision preserved with toLocal()
        expect(
          notif.createdAt,
          DateTime.parse('2026-09-05T08:30:15.123Z').toLocal(),
        );
        expect(notif.foodName, 'Milk');
        expect(notif.category, 'Dairy');
        expect(notif.quantity, 2);
        expect(notif.isExpiringSoon, true);
        expect(notif.isExpiresToday, false);
        expect(notif.isExpired, false);
      },
    );

    test('Correctly handles numeric-string IDs and type getters', () {
      final json = {
        'id': '202',
        'foodItemId': '99',
        'type': 'expires_today',
        'title': 'Eggs Expires Today',
        'message': 'Eggs expire today.',
        'isRead': true,
        'expiryDate': '2026-09-02',
        'createdAt': '2026-09-02T06:00:00.000Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 202);
      expect(notif.foodItemId, 99);
      expect(notif.isExpiresToday, true);
      expect(notif.isExpiringSoon, false);
      expect(notif.isExpired, false);
      expect(notif.isRead, true);
    });

    test('Expired type getter returns true for expired notification', () {
      final json = {
        'id': 303,
        'food_item_id': 12,
        'type': 'expired',
        'title': 'Yogurt Expired',
        'message': 'Yogurt has expired.',
        'is_read': false,
        'expiry_date': '2026-08-30',
        'created_at': '2026-09-01T00:00:00.000Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.isExpired, true);
      expect(notif.isExpiringSoon, false);
      expect(notif.isExpiresToday, false);
    });

    test('toJson excludes user_id from client payloads', () {
      final notif = AppNotification(
        id: 1,
        foodItemId: 10,
        type: 'expiring_soon',
        title: 'Apples',
        message: 'Apples expire soon',
        isRead: false,
        expiryDate: DateTime(2026, 9, 10),
        createdAt: DateTime(2026, 9, 2),
      );

      final json = notif.toJson();
      expect(json.containsKey('user_id'), false);
      expect(json.containsKey('userId'), false);
      expect(json['expiry_date'], '2026-09-10');
    });
  });

  group('NotificationPreferences Model Tests', () {
    test(
      'Correctly deserializes preferences JSON with defaults and sorted days',
      () {
        final json = {
          'notifications_enabled': true,
          'browser_notifications_enabled': false,
          'reminder_days': [1, 0, 7, 3],
          'timezone': 'America/New_York',
          'reminder_hour': 8,
        };

        final prefs = NotificationPreferences.fromJson(json);

        expect(prefs.notificationsEnabled, true);
        expect(prefs.browserNotificationsEnabled, false);
        // Automatically deduplicated and sorted descending [7, 3, 1, 0]
        expect(prefs.reminderDays, [7, 3, 1, 0]);
        expect(prefs.timezone, 'America/New_York');
        expect(prefs.reminderHour, 8);
      },
    );

    test('toUpdatePayload strictly excludes user_id and userId', () {
      const prefs = NotificationPreferences(
        notificationsEnabled: true,
        browserNotificationsEnabled: true,
        reminderDays: [3, 1],
        timezone: 'Asia/Kolkata',
        reminderHour: 9,
      );

      final payload = prefs.toUpdatePayload();

      expect(payload.containsKey('user_id'), false);
      expect(payload.containsKey('userId'), false);
      expect(payload['notifications_enabled'], true);
      expect(payload['browser_notifications_enabled'], true);
      expect(payload['reminder_days'], [3, 1]);
      expect(payload['timezone'], 'Asia/Kolkata');
      expect(payload['reminder_hour'], 9);
    });
  });
}
