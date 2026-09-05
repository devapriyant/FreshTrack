import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/api_config.dart';
import '../../../core/errors/exceptions.dart';
import '../models/otp_challenge_response.dart';
import '../models/user_profile.dart';

abstract class AuthRepository {
  /// Initiates user registration and requests an OTP challenge
  Future<OtpChallengeResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  });

  /// Verifies the registration OTP code to create the account
  Future<void> verifyRegistrationOtp({
    required String challengeId,
    required String otp,
  });

  /// Resends the registration OTP code
  Future<OtpChallengeResponse> resendRegistrationOtp({
    required String challengeId,
  });

  /// Initiates user login (step 1) and requests a login OTP challenge
  Future<OtpChallengeResponse> signIn({
    required String email,
    required String password,
  });

  /// Verifies the login OTP code (step 2) and saves the issued JWT
  Future<UserProfile> verifyLoginOtp({
    required String challengeId,
    required String otp,
  });

  /// Resends the login OTP code
  Future<OtpChallengeResponse> resendLoginOtp({
    required String challengeId,
  });

  /// Starts email verification for an existing unverified account
  Future<OtpChallengeResponse> startEmailVerification({
    required String email,
    required String password,
  });

  /// Verifies the email verification OTP code for an existing account
  Future<void> verifyEmailVerificationOtp({
    required String challengeId,
    required String otp,
  });

  /// Resends the email verification OTP code for an existing account
  Future<OtpChallengeResponse> resendEmailVerificationOtp({
    required String challengeId,
  });

  /// Signs out and deletes the stored JWT
  Future<void> signOut();

  /// Retrieves current profile of the authenticated user
  Future<UserProfile?> getCurrentProfile();

  /// Retrieves the current stored JWT
  Future<String?> getToken();

  /// Whether a valid token exists
  Future<bool> get isAuthenticated;

  /// Stream of authentication state changes
  Stream<bool> get authStateChanges;
}

class NodeAuthRepository implements AuthRepository {
  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage;
  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  static const String _tokenKey = 'freshtrack_jwt_token';

  NodeAuthRepository({
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  })  : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<String?> getToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> get isAuthenticated async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Stream<bool> get authStateChanges async* {
    yield await isAuthenticated;
    yield* _authStateController.stream;
  }

  @override
  Future<OtpChallengeResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.registerEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': fullName.trim(),
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 201) {
        return OtpChallengeResponse.fromJson(responseData);
      } else if (response.statusCode == 409) {
        throw AuthException(
          responseData['message'] as String? ??
              'An account with this email address already exists.',
          '409',
        );
      } else if (response.statusCode == 503) {
        throw AuthException(
          responseData['message'] as String? ??
              'Email delivery service is currently unavailable. Please try again later.',
          '503',
        );
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Registration failed.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException(
        'Unable to connect to server. Please ensure the backend is running.',
      );
    } on http.ClientException catch (e) {
      throw NetworkException('Network error during registration: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('An unexpected registration error occurred: $e');
    }
  }

  @override
  Future<void> verifyRegistrationOtp({
    required String challengeId,
    required String otp,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.registerVerifyOtpEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'challenge_id': challengeId.trim(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return;
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Verification failed.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Verification failed: $e');
    }
  }

  @override
  Future<OtpChallengeResponse> resendRegistrationOtp({
    required String challengeId,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.registerResendOtpEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'challenge_id': challengeId.trim()}),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return OtpChallengeResponse.fromJson(responseData);
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Failed to resend code.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Failed to resend code: $e');
    }
  }

  @override
  Future<OtpChallengeResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.loginEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return OtpChallengeResponse.fromJson(responseData);
      } else if (response.statusCode == 403 &&
          responseData['verification_required'] == true) {
        throw AuthException(
          responseData['message'] as String? ??
              'Email verification is required before logging in.',
          '403',
        );
      } else if (response.statusCode == 401) {
        throw AuthException(
          responseData['message'] as String? ?? 'Invalid email or password.',
          '401',
        );
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Login failed.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Login error: $e');
    }
  }

  @override
  Future<UserProfile> verifyLoginOtp({
    required String challengeId,
    required String otp,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.loginVerifyOtpEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'challenge_id': challengeId.trim(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        final token = responseData['token'] as String?;
        final userData = responseData['user'] as Map<String, dynamic>?;

        if (token == null || userData == null) {
          throw AuthException('Invalid server response: missing token or user.');
        }

        // Store JWT strictly after successful login OTP verification
        await _secureStorage.write(key: _tokenKey, value: token);
        _authStateController.add(true);

        return UserProfile.fromJson(userData);
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Verification failed.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Login verification error: $e');
    }
  }

  @override
  Future<OtpChallengeResponse> resendLoginOtp({
    required String challengeId,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.loginResendOtpEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'challenge_id': challengeId.trim()}),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return OtpChallengeResponse.fromJson(responseData);
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Failed to resend code.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Failed to resend code: $e');
    }
  }

  @override
  Future<OtpChallengeResponse> startEmailVerification({
    required String email,
    required String password,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.emailVerificationStartEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return OtpChallengeResponse.fromJson(responseData);
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Failed to start verification.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Failed to start verification: $e');
    }
  }

  @override
  Future<void> verifyEmailVerificationOtp({
    required String challengeId,
    required String otp,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.emailVerificationVerifyEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'challenge_id': challengeId.trim(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return;
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Verification failed.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Verification failed: $e');
    }
  }

  @override
  Future<OtpChallengeResponse> resendEmailVerificationOtp({
    required String challengeId,
  }) async {
    try {
      final url = Uri.parse(ApiConfig.emailVerificationResendEndpoint);
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'challenge_id': challengeId.trim()}),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> responseData = _decodeResponse(response.body);

      if (response.statusCode == 200) {
        return OtpChallengeResponse.fromJson(responseData);
      } else {
        throw AuthException(
          responseData['message'] as String? ?? 'Failed to resend code.',
          response.statusCode.toString(),
        );
      }
    } on SocketException catch (_) {
      throw NetworkException('Unable to connect to server.');
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: ${e.message}');
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw AuthException('Failed to resend code: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      _authStateController.add(false);
    } catch (e) {
      throw AuthException('Logout failed: $e');
    }
  }

  @override
  Future<UserProfile?> getCurrentProfile() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final url = Uri.parse(ApiConfig.profileEndpoint);
      final response = await _httpClient
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData =
            _decodeResponse(response.body);
        final userData = responseData['user'] as Map<String, dynamic>?;
        if (userData != null) {
          return UserProfile.fromJson(userData);
        }
        return null;
      } else if (response.statusCode == 401) {
        // Token invalid or expired - clear stored token
        await signOut();
        return null;
      } else {
        return null;
      }
    } on SocketException catch (_) {
      throw NetworkException(
        'Network connection failed while fetching profile.',
      );
    } catch (e) {
      if (e is FreshTrackException) rethrow;
      throw DatabaseException('Failed to fetch user profile: $e');
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

// Top-Level Riverpod Providers

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return NodeAuthRepository();
});

final authStateProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authStateAsync = ref.watch(authStateProvider);
  final isAuthed = authStateAsync.value ?? false;
  if (!isAuthed) return null;

  final repo = ref.watch(authRepositoryProvider);
  return repo.getCurrentProfile();
});
