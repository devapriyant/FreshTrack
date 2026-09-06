import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/auth/session_expiry_coordinator.dart';
import '../../../core/config/api_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../auth/data/auth_repository.dart';
import '../models/app_notification.dart';
import '../models/notification_preferences.dart';

abstract class NotificationRepository {
  Future<List<AppNotification>> getNotifications({
    bool? unread,
    String? type,
    int limit = 30,
    int offset = 0,
  });

  Future<int> getUnreadCount();

  Future<AppNotification> markAsRead(int id);

  Future<int> markAllAsRead();

  Future<void> deleteNotification(int id);

  Future<NotificationPreferences> getPreferences();

  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences preferences,
  );

  void dispose();
}

class NodeNotificationRepository implements NotificationRepository {
  final AuthRepository authRepository;
  final SessionExpiryCoordinator sessionExpiryCoordinator;
  final http.Client _httpClient;
  final bool _isClientOwned;

  NodeNotificationRepository({
    required this.authRepository,
    required this.sessionExpiryCoordinator,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client(),
       _isClientOwned = httpClient == null;

  @override
  void dispose() {
    if (_isClientOwned) {
      _httpClient.close();
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await authRepository.getToken();
    if (token == null || token.isEmpty) {
      await sessionExpiryCoordinator.expireSession();
      throw AuthException(
        'Authentication token required. Please log in.',
        '401',
      );
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _handleErrorResponse(http.Response response) async {
    final body = _decodeResponse(response.body);
    final message =
        body['message']?.toString() ??
        'Request failed with status code ${response.statusCode}';

    switch (response.statusCode) {
      case 400:
        throw ValidationException(message, '400');
      case 401:
        // Authoritatively clear session and advance epoch via coordinator
        await sessionExpiryCoordinator.expireSession();
        throw AuthException(message, '401');
      case 404:
        throw NotFoundException(message, '404');
      default:
        throw DatabaseException(message, response.statusCode.toString());
    }
  }

  @override
  Future<List<AppNotification>> getNotifications({
    bool? unread,
    String? type,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final headers = await _getHeaders();
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

      if (unread != null) {
        queryParams['unread'] = unread.toString();
      }
      if (type != null && type.isNotEmpty) {
        queryParams['type'] = type;
      }

      final uri = Uri.parse(
        ApiConfig.notificationsEndpoint,
      ).replace(queryParameters: queryParams);

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        final rawList = data['notifications'] as List<dynamic>? ?? [];
        return rawList
            .map(
              (item) => AppNotification.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } else {
        await _handleErrorResponse(response);
        return [];
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while loading notifications: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the notifications server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to load notifications: $e');
    }
  }

  @override
  Future<int> getUnreadCount() async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationUnreadCountEndpoint);

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return int.tryParse(data['unread_count']?.toString() ?? '0') ?? 0;
      } else {
        await _handleErrorResponse(response);
        return 0;
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while loading unread notification count: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to load unread count: $e');
    }
  }

  @override
  Future<AppNotification> markAsRead(int id) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationReadEndpoint(id));

      final response = await _httpClient
          .patch(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return AppNotification.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while marking notification as read: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to mark notification as read: $e');
    }
  }

  @override
  Future<int> markAllAsRead() async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationReadAllEndpoint);

      final response = await _httpClient
          .patch(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return int.tryParse(data['updated_count']?.toString() ?? '0') ?? 0;
      } else {
        await _handleErrorResponse(response);
        return 0;
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while marking all notifications as read: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to mark all notifications as read: $e');
    }
  }

  @override
  Future<void> deleteNotification(int id) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationDeleteEndpoint(id));

      final response = await _httpClient
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return;
      } else {
        await _handleErrorResponse(response);
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while deleting notification: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to delete notification: $e');
    }
  }

  @override
  Future<NotificationPreferences> getPreferences() async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationPreferencesEndpoint);

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return NotificationPreferences.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        return const NotificationPreferences();
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while loading notification preferences: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to load preferences: $e');
    }
  }

  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences preferences,
  ) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.notificationPreferencesEndpoint);

      final response = await _httpClient
          .put(
            uri,
            headers: headers,
            body: jsonEncode(preferences.toUpdatePayload()),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return NotificationPreferences.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while updating notification preferences: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to update preferences: $e');
    }
  }
}
