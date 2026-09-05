import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  /// Gets the appropriate base URL based on platform and environment configuration
  static String get baseUrl {
    // Check if custom override is defined in .env
    if (dotenv.isInitialized) {
      final envUrl = dotenv.maybeGet('API_BASE_URL');
      if (envUrl != null && envUrl.isNotEmpty) {
        return envUrl;
      }
    }

    // Flutter Web
    if (kIsWeb) {
      return 'http://localhost:5000';
    }

    // Android Emulator requires 10.0.2.2 to access host localhost
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5000';
      }
    } catch (_) {
      // Platform check may fail on unsupported platforms
    }

    // Default for iOS Simulator, desktop (Windows, macOS, Linux)
    return 'http://localhost:5000';
  }

  static String get registerEndpoint => '$baseUrl/api/auth/register';
  static String get registerVerifyOtpEndpoint =>
      '$baseUrl/api/auth/register/verify-otp';
  static String get registerResendOtpEndpoint =>
      '$baseUrl/api/auth/register/resend-otp';

  static String get loginEndpoint => '$baseUrl/api/auth/login';
  static String get loginVerifyOtpEndpoint =>
      '$baseUrl/api/auth/login/verify-otp';
  static String get loginResendOtpEndpoint =>
      '$baseUrl/api/auth/login/resend-otp';

  static String get emailVerificationStartEndpoint =>
      '$baseUrl/api/auth/email-verification/start';
  static String get emailVerificationVerifyEndpoint =>
      '$baseUrl/api/auth/email-verification/verify';
  static String get emailVerificationResendEndpoint =>
      '$baseUrl/api/auth/email-verification/resend';

  static String get profileEndpoint => '$baseUrl/api/auth/profile';

  static String get foodsEndpoint => '$baseUrl/api/foods';
  static String foodDetailEndpoint(int id) => '$baseUrl/api/foods/$id';
  static String foodStatusEndpoint(int id) => '$baseUrl/api/foods/$id/status';

  static String get notificationsEndpoint => '$baseUrl/api/notifications';
  static String get notificationUnreadCountEndpoint =>
      '$baseUrl/api/notifications/unread-count';
  static String notificationReadEndpoint(int id) =>
      '$baseUrl/api/notifications/$id/read';
  static String get notificationReadAllEndpoint =>
      '$baseUrl/api/notifications/read-all';
  static String notificationDeleteEndpoint(int id) =>
      '$baseUrl/api/notifications/$id';
  static String get notificationPreferencesEndpoint =>
      '$baseUrl/api/notification-preferences';
}
