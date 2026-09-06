import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freshtrack/core/auth/session_expiry_coordinator.dart';
import 'package:freshtrack/core/errors/exceptions.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/food/data/food_repository.dart';
import 'package:freshtrack/features/auth/models/otp_challenge_response.dart';

// Fake AuthRepository for testing
class FakeAuthRepository implements AuthRepository {
  String? token = 'fake_jwt_token';
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

class FakeSessionExpiryCoordinator implements SessionExpiryCoordinator {
  bool expireSessionCalled = false;
  int expireSessionCallCount = 0;

  @override
  Future<void> expireSession() async {
    expireSessionCalled = true;
    expireSessionCallCount++;
  }
}

void main() {
  group('NodeFoodRepository Tests', () {
    late FakeAuthRepository fakeAuth;
    late FakeSessionExpiryCoordinator fakeCoordinator;

    setUp(() {
      fakeAuth = FakeAuthRepository();
      fakeCoordinator = FakeSessionExpiryCoordinator();
    });

    test(
      'getFoods sends Authorization header and returns parsed FoodItems',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fake_jwt_token');
          expect(request.url.path, '/api/foods');

          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 1,
                  'user_id': 10,
                  'food_name': 'Milk',
                  'category': 'Dairy',
                  'quantity': 1,
                  'expiry_date': '2026-09-10',
                  'status': 'active',
                  'created_at': '2026-09-01T00:00:00.000Z',
                  'updated_at': '2026-09-01T00:00:00.000Z',
                },
              ],
              'count': 1,
            }),
            200,
          );
        });

        final repo = NodeFoodRepository(
          authRepository: fakeAuth,
          sessionExpiryCoordinator: fakeCoordinator,
          httpClient: mockClient,
        );

        final items = await repo.getFoods();
        expect(items.length, 1);
        expect(items.first.foodName, 'Milk');
        expect(items.first.id, 1);
      },
    );

    test('getFoods with query filters passes query parameters', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['status'], 'active');
        expect(request.url.queryParameters['category'], 'Produce');
        expect(request.url.queryParameters['search'], 'apple');

        return http.Response(jsonEncode({'items': [], 'count': 0}), 200);
      });

      final repo = NodeFoodRepository(
        authRepository: fakeAuth,
        sessionExpiryCoordinator: fakeCoordinator,
        httpClient: mockClient,
      );

      final items = await repo.getFoods(
        status: 'active',
        category: 'Produce',
        search: 'apple',
      );
      expect(items, isEmpty);
    });

    test(
      'addFood sends POST with payload and returns created FoodItem',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['food_name'], 'Eggs');
          expect(body['quantity'], 12);

          return http.Response(
            jsonEncode({
              'id': 15,
              'user_id': 10,
              'food_name': 'Eggs',
              'quantity': 12,
              'expiry_date': '2026-09-20',
              'status': 'active',
              'created_at': '2026-09-01T00:00:00.000Z',
              'updated_at': '2026-09-01T00:00:00.000Z',
            }),
            201,
          );
        });

        final repo = NodeFoodRepository(
          authRepository: fakeAuth,
          sessionExpiryCoordinator: fakeCoordinator,
          httpClient: mockClient,
        );

        final item = await repo.addFood({
          'food_name': 'Eggs',
          'quantity': 12,
          'expiry_date': '2026-09-20',
        });
        expect(item.id, 15);
        expect(item.foodName, 'Eggs');
        expect(item.quantity, 12);
      },
    );

    test('updateStatus sends PATCH and returns updated FoodItem', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/foods/15/status');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 'consumed');

        return http.Response(
          jsonEncode({
            'id': 15,
            'user_id': 10,
            'food_name': 'Eggs',
            'quantity': 12,
            'expiry_date': '2026-09-20',
            'status': 'consumed',
            'created_at': '2026-09-01T00:00:00.000Z',
            'updated_at': '2026-09-01T01:00:00.000Z',
          }),
          200,
        );
      });

      final repo = NodeFoodRepository(
        authRepository: fakeAuth,
        sessionExpiryCoordinator: fakeCoordinator,
        httpClient: mockClient,
      );

      final item = await repo.updateStatus(15, 'consumed');
      expect(item.status, 'consumed');
    });

    test('HTTP 400 maps to ValidationException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Quantity must be positive'}),
          400,
        );
      });

      final repo = NodeFoodRepository(
        authRepository: fakeAuth,
        sessionExpiryCoordinator: fakeCoordinator,
        httpClient: mockClient,
      );

      expect(
        () => repo.addFood({'food_name': 'Bad', 'quantity': -1}),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Quantity must be positive',
          ),
        ),
      );
    });

    test(
      'HTTP 401 calls sessionExpiryCoordinator.expireSession() and throws AuthException',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'message': 'Invalid or expired token'}),
            401,
          );
        });

        final repo = NodeFoodRepository(
          authRepository: fakeAuth,
          sessionExpiryCoordinator: fakeCoordinator,
          httpClient: mockClient,
        );

        expect(fakeCoordinator.expireSessionCalled, isFalse);

        await expectLater(
          () => repo.getFoods(),
          throwsA(isA<AuthException>().having((e) => e.code, 'code', '401')),
        );

        expect(fakeCoordinator.expireSessionCalled, isTrue);
        expect(fakeCoordinator.expireSessionCallCount, 1);
      },
    );

    test('HTTP 404 maps to NotFoundException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Food item not found.'}),
          404,
        );
      });

      final repo = NodeFoodRepository(
        authRepository: fakeAuth,
        sessionExpiryCoordinator: fakeCoordinator,
        httpClient: mockClient,
      );

      expect(
        () => repo.getFood(999),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            'Food item not found.',
          ),
        ),
      );
    });

    test('HTTP 500 maps to DatabaseException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Database error'}), 500);
      });

      final repo = NodeFoodRepository(
        authRepository: fakeAuth,
        sessionExpiryCoordinator: fakeCoordinator,
        httpClient: mockClient,
      );

      expect(() => repo.getFoods(), throwsA(isA<DatabaseException>()));
    });
  });
}
