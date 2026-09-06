import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/features/auth/data/auth_repository.dart';
import 'package:freshtrack/features/auth/models/otp_challenge_response.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';
import 'package:freshtrack/features/auth/screens/otp_screen.dart';

class MockOtpAuthRepository implements AuthRepository {
  String? verifiedRegChallenge;
  String? verifiedRegOtp;
  String? verifiedLoginChallenge;
  String? verifiedLoginOtp;
  String? verifiedEmailChallenge;
  String? verifiedEmailOtp;

  bool resendCalled = false;
  bool shouldFail = false;

  @override
  Future<void> verifyRegistrationOtp({
    required String challengeId,
    required String otp,
  }) async {
    if (shouldFail) throw Exception('Invalid OTP code');
    verifiedRegChallenge = challengeId;
    verifiedRegOtp = otp;
  }

  @override
  Future<UserProfile> verifyLoginOtp({
    required String challengeId,
    required String otp,
  }) async {
    if (shouldFail) throw Exception('Invalid login code');
    verifiedLoginChallenge = challengeId;
    verifiedLoginOtp = otp;
    return UserProfile(
      id: '42',
      userId: '42',
      fullName: 'Verified User',
      email: 'verified@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> verifyEmailVerificationOtp({
    required String challengeId,
    required String otp,
  }) async {
    if (shouldFail) throw Exception('Verification failed');
    verifiedEmailChallenge = challengeId;
    verifiedEmailOtp = otp;
  }

  @override
  Future<OtpChallengeResponse> resendRegistrationOtp({
    required String challengeId,
  }) async {
    resendCalled = true;
    return const OtpChallengeResponse(
      challengeId: 'new-reg-id',
      maskedEmail: 't***@example.com',
      expiresInSeconds: 600,
      message: 'New code sent',
    );
  }

  @override
  Future<OtpChallengeResponse> resendLoginOtp({
    required String challengeId,
  }) async {
    resendCalled = true;
    return const OtpChallengeResponse(
      challengeId: 'new-login-id',
      maskedEmail: 't***@example.com',
      expiresInSeconds: 600,
      message: 'New code sent',
    );
  }

  @override
  Future<OtpChallengeResponse> resendEmailVerificationOtp({
    required String challengeId,
  }) async {
    resendCalled = true;
    return const OtpChallengeResponse(
      challengeId: 'new-email-id',
      maskedEmail: 't***@example.com',
      expiresInSeconds: 600,
      message: 'New code sent',
    );
  }

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<UserProfile?> getCurrentProfile() async => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<bool> get isAuthenticated async => false;

  @override
  Future<OtpChallengeResponse> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<OtpChallengeResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async => throw UnimplementedError();

  @override
  Future<OtpChallengeResponse> startEmailVerification({
    required String email,
    required String password,
  }) async => throw UnimplementedError();
}

void main() {
  group('OtpChallengeResponse Model Tests', () {
    test(
      'Correctly deserializes JSON payload with string and integer fields',
      () {
        final json = {
          'challenge_id': 'uuid-challenge-123',
          'email': 'd***@example.com',
          'expires_in_seconds': 600,
          'message': 'Verification code sent.',
          'verification_required': true,
        };

        final response = OtpChallengeResponse.fromJson(json);

        expect(response.challengeId, 'uuid-challenge-123');
        expect(response.maskedEmail, 'd***@example.com');
        expect(response.expiresInSeconds, 600);
        expect(response.message, 'Verification code sent.');
        expect(response.verificationRequired, isTrue);
      },
    );
  });

  group('OtpScreen Widget Tests', () {
    late MockOtpAuthRepository mockAuth;

    setUp(() {
      mockAuth = MockOtpAuthRepository();
    });

    Widget createTestApp(Widget home) {
      return ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(mockAuth)],
        child: MaterialApp(home: home),
      );
    }

    testWidgets(
      'Renders registration OTP UI with masked email and 6-digit boxes',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const OtpScreen(
              challengeId: 'reg-challenge-1',
              email: 'u***@example.com',
              purpose: OtpPurpose.register,
              expiresInSeconds: 600,
            ),
          ),
        );

        expect(find.text('Verify Your Email'), findsOneWidget);
        expect(find.textContaining('u***@example.com'), findsOneWidget);
        expect(find.text('Verify & Continue'), findsOneWidget);
        expect(find.textContaining('Resend in'), findsOneWidget);
      },
    );

    testWidgets('Submitting 6-digit OTP calls verifyRegistrationOtp', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          const OtpScreen(
            challengeId: 'reg-challenge-1',
            email: 'u***@example.com',
            purpose: OtpPurpose.register,
            expiresInSeconds: 600,
          ),
        ),
      );

      // Enter 6-digit OTP into hidden TextField
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, '123456');
      await tester.pumpAndSettle();

      expect(mockAuth.verifiedRegChallenge, 'reg-challenge-1');
      expect(mockAuth.verifiedRegOtp, '123456');
    });

    testWidgets(
      'Submitting login OTP calls verifyLoginOtp and session controller',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const OtpScreen(
              challengeId: 'login-challenge-1',
              email: 'u***@example.com',
              purpose: OtpPurpose.login,
              expiresInSeconds: 600,
            ),
          ),
        );

        expect(find.text('Login Verification'), findsOneWidget);

        final textField = find.byType(TextField);
        await tester.enterText(textField, '654321');
        await tester.pumpAndSettle();

        expect(mockAuth.verifiedLoginChallenge, 'login-challenge-1');
        expect(mockAuth.verifiedLoginOtp, '654321');
      },
    );

    testWidgets('Short OTP displays validation snackbar', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const OtpScreen(
            challengeId: 'reg-challenge-1',
            email: 'u***@example.com',
            purpose: OtpPurpose.register,
            expiresInSeconds: 600,
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '123');
      await tester.tap(find.text('Verify & Continue'));
      await tester.pump();

      expect(
        find.text('Please enter a complete 6-digit OTP code.'),
        findsOneWidget,
      );
    });
  });
}
