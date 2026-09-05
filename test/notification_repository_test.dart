import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freshtrack/core/errors/exceptions.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/notifications/data/notification_repository.dart';
import 'package:freshtrack/features/notifications/models/notification_preferences.dart';

import 'package:freshtrack/features/auth/models/otp_challenge_response.dart';

class FakeAuthRepository implements AuthRepository {
  String? token = 'mock_jwt_token';
  bool signOutCalled = false;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    token = null;
  }

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<UserProfile?> getCurrentProfile() async => null;

  @override
  Future<bool> get isAuthenticated async => token != null;

  @override
  Future<OtpChallengeResponse> signIn({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> verifyLoginOtp({
    required String challengeId,
    required String otp,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OtpChallengeResponse> resendLoginOtp({
    required String challengeId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OtpChallengeResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> verifyRegistrationOtp({
    required String challengeId,
    required String otp,
  }) async {}

  @override
  Future<OtpChallengeResponse> resendRegistrationOtp({
    required String challengeId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OtpChallengeResponse> startEmailVerification({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> verifyEmailVerificationOtp({
    required String challengeId,
    required String otp,
  }) async {}

  @override
  Future<OtpChallengeResponse> resendEmailVerificationOtp({
    required String challengeId,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  group('NodeNotificationRepository Tests', () {
    late FakeAuthRepository authRepo;

    setUp(() {
      authRepo = FakeAuthRepository();
    });

    test(
      'getNotifications sends Bearer token, query params, and parses list',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer mock_jwt_token');
          expect(request.url.queryParameters['limit'], '20');
          expect(request.url.queryParameters['offset'], '5');
          expect(request.url.queryParameters['unread'], 'true');

          final responsePayload = {
            'notifications': [
              {
                'id': 1,
                'food_item_id': 10,
                'type': 'expiring_soon',
                'title': 'Milk Alert',
                'message': 'Milk expires in 3 days.',
                'is_read': false,
                'expiry_date': '2026-09-08',
                'created_at': '2026-09-05T08:00:00.000Z',
              },
            ],
            'unread_count': 1,
            'total': 1,
          };

          return http.Response(
            jsonEncode(responsePayload),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final repo = NodeNotificationRepository(
          authRepository: authRepo,
          httpClient: mockClient,
        );

        final list = await repo.getNotifications(
          unread: true,
          limit: 20,
          offset: 5,
        );

        expect(list.length, 1);
        expect(list.first.id, 1);
        expect(list.first.foodItemId, 10);
        expect(list.first.isExpiringSoon, true);
      },
    );

    test('getUnreadCount returns integer count', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/api/notifications/unread-count'));
        return http.Response(
          jsonEncode({'unread_count': 5}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = NodeNotificationRepository(
        authRepository: authRepo,
        httpClient: mockClient,
      );

      final count = await repo.getUnreadCount();
      expect(count, 5);
    });

    test(
      'markAsRead sends PATCH to read endpoint and returns notification',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, endsWith('/api/notifications/42/read'));

          final payload = {
            'id': 42,
            'food_item_id': 5,
            'type': 'expires_today',
            'title': 'Bread Alert',
            'message': 'Bread expires today.',
            'is_read': true,
            'expiry_date': '2026-09-02',
            'created_at': '2026-09-02T08:00:00.000Z',
          };

          return http.Response(
            jsonEncode(payload),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final repo = NodeNotificationRepository(
          authRepository: authRepo,
          httpClient: mockClient,
        );

        final result = await repo.markAsRead(42);
        expect(result.id, 42);
        expect(result.isRead, true);
      },
    );

    test(
      'markAllAsRead sends PATCH to read-all and returns updated count',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, endsWith('/api/notifications/read-all'));

          return http.Response(
            jsonEncode({
              'message': 'All notifications marked as read.',
              'updated_count': 3,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final repo = NodeNotificationRepository(
          authRepository: authRepo,
          httpClient: mockClient,
        );

        final count = await repo.markAllAsRead();
        expect(count, 3);
      },
    );

    test('deleteNotification sends DELETE to item endpoint', () async {
      bool deleteCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, endsWith('/api/notifications/77'));
        deleteCalled = true;

        return http.Response(
          jsonEncode({'message': 'Notification deleted successfully.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = NodeNotificationRepository(
        authRepository: authRepo,
        httpClient: mockClient,
      );

      await repo.deleteNotification(77);
      expect(deleteCalled, true);
    });

    test(
      'updatePreferences sends PUT with payload and returns updated preferences',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, endsWith('/api/notification-preferences'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('user_id'), false);
          expect(body['notifications_enabled'], true);
          expect(body['reminder_days'], [7, 3, 1, 0]);

          return http.Response(
            request.body,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final repo = NodeNotificationRepository(
          authRepository: authRepo,
          httpClient: mockClient,
        );

        const prefs = NotificationPreferences(
          notificationsEnabled: true,
          browserNotificationsEnabled: false,
          reminderDays: [7, 3, 1, 0],
          timezone: 'Asia/Kolkata',
          reminderHour: 9,
        );

        final updated = await repo.updatePreferences(prefs);
        expect(updated.notificationsEnabled, true);
        expect(updated.reminderDays, [7, 3, 1, 0]);
      },
    );

    test('HTTP 400 maps to ValidationException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid reminder hour.'}),
          400,
        );
      });

      final repo = NodeNotificationRepository(
        authRepository: authRepo,
        httpClient: mockClient,
      );

      expect(() => repo.getUnreadCount(), throwsA(isA<ValidationException>()));
    });

    test(
      'HTTP 401 calls authRepository.signOut() and throws AuthException',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'message': 'Invalid token.'}), 401);
        });

        final repo = NodeNotificationRepository(
          authRepository: authRepo,
          httpClient: mockClient,
        );

        expect(() => repo.getUnreadCount(), throwsA(isA<AuthException>()));
        // Let microtasks run
        await Future.delayed(Duration.zero);
        expect(authRepo.signOutCalled, true);
      },
    );

    test('HTTP 404 maps to NotFoundException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Notification not found.'}),
          404,
        );
      });

      final repo = NodeNotificationRepository(
        authRepository: authRepo,
        httpClient: mockClient,
      );

      expect(() => repo.markAsRead(999), throwsA(isA<NotFoundException>()));
    });

    test('HTTP 500 maps to DatabaseException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Database connection error.'}),
          500,
        );
      });

      final repo = NodeNotificationRepository(
        authRepository: authRepo,
        httpClient: mockClient,
      );

      expect(() => repo.getUnreadCount(), throwsA(isA<DatabaseException>()));
    });
  });
}
