import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/features/auth/controllers/auth_session_controller.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/otp_challenge_response.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/food/data/food_repository.dart';
import 'package:freshtrack/features/food/models/food_item.dart';
import 'package:freshtrack/features/food/providers/food_providers.dart';

class MockIsolatedAuthRepository implements AuthRepository {
  UserProfile? _currentProfile;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  void setCurrentUser(UserProfile? user) {
    _currentProfile = user;
    _controller.add(user != null);
  }

  @override
  Stream<bool> get authStateChanges async* {
    yield _currentProfile != null;
    yield* _controller.stream;
  }

  @override
  Future<UserProfile?> getCurrentProfile() async => _currentProfile;

  @override
  Future<String?> getToken() async => _currentProfile != null ? 'test_token' : null;

  @override
  Future<bool> get isAuthenticated async => _currentProfile != null;

  @override
  Future<void> signOut() async {
    _currentProfile = null;
    _controller.add(false);
  }

  @override
  Future<OtpChallengeResponse> signIn({required String email, required String password}) async {
    return const OtpChallengeResponse(
      challengeId: 'c-123',
      maskedEmail: 't***@example.com',
      expiresInSeconds: 600,
      message: 'Code sent',
    );
  }

  @override
  Future<UserProfile> verifyLoginOtp({required String challengeId, required String otp}) async {
    final user = UserProfile(
      id: '1',
      userId: '1',
      fullName: 'User A',
      email: 'usera@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _currentProfile = user;
    _controller.add(true);
    return user;
  }

  @override
  Future<OtpChallengeResponse> signUp({required String email, required String password, required String fullName}) async {
    return const OtpChallengeResponse(
      challengeId: 'c-reg',
      maskedEmail: 't***@example.com',
      expiresInSeconds: 600,
      message: 'Code sent',
    );
  }

  @override
  Future<void> verifyRegistrationOtp({required String challengeId, required String otp}) async {}

  @override
  Future<OtpChallengeResponse> resendRegistrationOtp({required String challengeId}) async => throw UnimplementedError();

  @override
  Future<OtpChallengeResponse> resendLoginOtp({required String challengeId}) async => throw UnimplementedError();

  @override
  Future<OtpChallengeResponse> startEmailVerification({required String email, required String password}) async => throw UnimplementedError();

  @override
  Future<void> verifyEmailVerificationOtp({required String challengeId, required String otp}) async => throw UnimplementedError();

  @override
  Future<OtpChallengeResponse> resendEmailVerificationOtp({required String challengeId}) async => throw UnimplementedError();
}

class MockIsolatedFoodRepository implements FoodRepository {
  final Map<String, List<FoodItem>> userFoods = {};
  Completer<List<FoodItem>>? delayedResponseCompleter;

  String? currentUserId;

  @override
  Future<List<FoodItem>> getFoods({String? status, String? category, String? storageLocation, String? search}) async {
    if (delayedResponseCompleter != null) {
      return await delayedResponseCompleter!.future;
    }
    return userFoods[currentUserId] ?? [];
  }

  @override
  Future<FoodItem> addFood(Map<String, dynamic> payload) async {
    final list = userFoods[currentUserId] ?? [];
    final item = FoodItem(
      id: list.length + 1,
      userId: int.tryParse(currentUserId ?? '1') ?? 1,
      foodName: payload['food_name'] as String,
      category: payload['category'] as String?,
      quantity: payload['quantity'] as int? ?? 1,
      expiryDate: DateTime.parse(payload['expiry_date'] as String),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    list.add(item);
    userFoods[currentUserId!] = list;
    return item;
  }

  @override
  Future<void> deleteFood(int id) async {}

  @override
  void dispose() {}

  @override
  Future<FoodItem> getFood(int id) async => throw UnimplementedError();

  @override
  Future<FoodItem> updateFood(int id, Map<String, dynamic> payload) async => throw UnimplementedError();

  @override
  Future<FoodItem> updateStatus(int id, String status) async => throw UnimplementedError();
}

void main() {
  group('Cross-User Cache & Session Isolation Tests', () {
    late MockIsolatedAuthRepository mockAuth;
    late MockIsolatedFoodRepository mockFood;
    late ProviderContainer container;

    final userAProfile = UserProfile(
      id: '1',
      userId: '1',
      fullName: 'User A',
      email: 'usera@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final userBProfile = UserProfile(
      id: '2',
      userId: '2',
      fullName: 'User B',
      email: 'userb@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setUp(() {
      mockAuth = MockIsolatedAuthRepository();
      mockFood = MockIsolatedFoodRepository();

      // Seed User A's private food item
      mockFood.userFoods['1'] = [
        FoodItem(
          id: 101,
          userId: 1,
          foodName: 'USER_A_PRIVATE_FOOD',
          category: 'Produce',
          quantity: 2,
          expiryDate: DateTime.now().add(const Duration(days: 5)),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      // Seed User B's independent food item
      mockFood.userFoods['2'] = [
        FoodItem(
          id: 201,
          userId: 2,
          foodName: 'USER_B_INDEPENDENT_FOOD',
          category: 'Dairy',
          quantity: 1,
          expiryDate: DateTime.now().add(const Duration(days: 10)),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          foodRepositoryProvider.overrideWithValue(mockFood),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('User A logs in -> sees private food -> logs out -> User B logs in -> User A data never flashes or leaks', () async {
      // 1. User A logs in
      mockFood.currentUserId = '1';
      mockAuth.setCurrentUser(userAProfile);

      // Read food items for User A
      final userAItems = await container.read(allFoodItemsProvider.future);
      expect(userAItems.length, 1);
      expect(userAItems.first.foodName, 'USER_A_PRIVATE_FOOD');

      final statsA = container.read(foodStatsProvider);
      expect(statsA.totalCount, 1);
      expect(statsA.activeCount, 1);

      // 2. User A logs out via centralized AuthSessionController
      await container.read(authSessionControllerProvider.notifier).signOut();

      // Immediately verify allFoodItemsProvider returns empty list when unauthenticated
      final unauthedItems = await container.read(allFoodItemsProvider.future);
      expect(unauthedItems.isEmpty, isTrue);

      final unauthedStats = container.read(foodStatsProvider);
      expect(unauthedStats.totalCount, 0);

      // 3. User B logs in
      mockFood.currentUserId = '2';
      mockAuth.setCurrentUser(userBProfile);
      container.read(authSessionControllerProvider.notifier).onSessionStarted();

      // Read food items for User B
      final userBItems = await container.read(allFoodItemsProvider.future);
      expect(userBItems.length, 1);
      expect(userBItems.first.foodName, 'USER_B_INDEPENDENT_FOOD');

      // CRITICAL CHECK: User A's food item is completely absent
      expect(userBItems.any((item) => item.foodName == 'USER_A_PRIVATE_FOOD'), isFalse);

      final statsB = container.read(foodStatsProvider);
      expect(statsB.totalCount, 1);
      expect(statsB.activeCount, 1);
    });

    test('Session Epoch Guard: late in-flight HTTP responses from earlier session are discarded', () async {
      // 1. User A starts loading inventory with an artificial delay
      mockFood.currentUserId = '1';
      mockAuth.setCurrentUser(userAProfile);
      mockFood.delayedResponseCompleter = Completer<List<FoodItem>>();

      // Trigger build() which will wait on the delayed completer
      final future = container.read(allFoodItemsProvider.future);

      // 2. Before response arrives, User A logs out
      await container.read(authSessionControllerProvider.notifier).signOut();

      // 3. Late response for User A arrives now
      mockFood.delayedResponseCompleter!.complete([
        FoodItem(
          id: 999,
          userId: 1,
          foodName: 'LATE_USER_A_STALE_FOOD',
          quantity: 1,
          expiryDate: DateTime.now().add(const Duration(days: 1)),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      // Await User A's pending call
      final resultOfDelayedCall = await future;

      // Because epoch changed and user logged out, the build guard returned empty list!
      expect(resultOfDelayedCall.isEmpty, isTrue);

      // 4. Now User B logs in
      mockFood.currentUserId = '2';
      mockAuth.setCurrentUser(userBProfile);
      container.read(authSessionControllerProvider.notifier).onSessionStarted();

      mockFood.delayedResponseCompleter = null;
      final userBItems = await container.read(allFoodItemsProvider.future);
      expect(userBItems.length, 1);
      expect(userBItems.first.foodName, 'USER_B_INDEPENDENT_FOOD');
      expect(userBItems.any((item) => item.foodName == 'LATE_USER_A_STALE_FOOD'), isFalse);
    });
  });
}
