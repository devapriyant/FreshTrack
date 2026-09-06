import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/auth/session_expiry_coordinator.dart';
import '../../../core/config/api_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../auth/data/auth_repository.dart';
import '../models/food_item.dart';

abstract class FoodRepository {
  Future<List<FoodItem>> getFoods({
    String? status,
    String? category,
    String? storageLocation,
    String? search,
  });

  Future<FoodItem> getFood(int id);

  Future<FoodItem> addFood(Map<String, dynamic> payload);

  Future<FoodItem> updateFood(int id, Map<String, dynamic> payload);

  Future<FoodItem> updateStatus(int id, String status);

  Future<void> deleteFood(int id);

  void dispose();
}

class NodeFoodRepository implements FoodRepository {
  final AuthRepository authRepository;
  final SessionExpiryCoordinator sessionExpiryCoordinator;
  final http.Client _httpClient;
  final bool _isClientOwned;

  NodeFoodRepository({
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
  Future<List<FoodItem>> getFoods({
    String? status,
    String? category,
    String? storageLocation,
    String? search,
  }) async {
    try {
      final headers = await _getHeaders();
      final queryParams = <String, String>{};

      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      if (storageLocation != null && storageLocation.isNotEmpty) {
        queryParams['storage_location'] = storageLocation;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final uri = Uri.parse(
        ApiConfig.foodsEndpoint,
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        final rawItems = data['items'] as List<dynamic>? ?? [];
        return rawItems
            .map((item) => FoodItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        await _handleErrorResponse(response);
        return [];
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while loading food items: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to load food items: $e');
    }
  }

  @override
  Future<FoodItem> getFood(int id) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.foodDetailEndpoint(id));

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return FoodItem.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while fetching food item: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to fetch food item: $e');
    }
  }

  @override
  Future<FoodItem> addFood(Map<String, dynamic> payload) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.foodsEndpoint);

      final response = await _httpClient
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = _decodeResponse(response.body);
        return FoodItem.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while adding food item: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to add food item: $e');
    }
  }

  @override
  Future<FoodItem> updateFood(int id, Map<String, dynamic> payload) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.foodDetailEndpoint(id));

      final response = await _httpClient
          .put(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return FoodItem.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while updating food item: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to update food item: $e');
    }
  }

  @override
  Future<FoodItem> updateStatus(int id, String status) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.foodStatusEndpoint(id));

      final response = await _httpClient
          .patch(
            uri,
            headers: headers,
            body: jsonEncode({'status': status.trim().toLowerCase()}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = _decodeResponse(response.body);
        return FoodItem.fromJson(data);
      } else {
        await _handleErrorResponse(response);
        throw DatabaseException('Unreachable');
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while updating food status: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to update food status: $e');
    }
  }

  @override
  Future<void> deleteFood(int id) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(ApiConfig.foodDetailEndpoint(id));

      final response = await _httpClient
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return;
      } else {
        await _handleErrorResponse(response);
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network error while deleting food item: ${e.message}',
      );
    } on TimeoutException {
      throw NetworkException(
        'Request timed out while connecting to the server.',
      );
    } on FreshTrackException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to delete food item: $e');
    }
  }
}
