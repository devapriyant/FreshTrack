import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/core/config/api_config.dart';
import 'package:freshtrack/features/auth/models/user_profile.dart';

void main() {
  group('UserProfile Model Tests', () {
    test('Correctly deserializes PostgreSQL JSON with integer ID and name', () {
      final json = {
        'id': 1,
        'name': 'Deva User',
        'email': 'deva@example.com',
        'created_at': '2026-09-01T05:00:00.000Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, '1');
      expect(profile.fullName, 'Deva User');
      expect(profile.email, 'deva@example.com');
      expect(profile.createdAt, DateTime.parse('2026-09-01T05:00:00.000Z'));
      expect(profile.updatedAt, DateTime.parse('2026-09-01T05:00:00.000Z'));
    });

    test(
      'Correctly deserializes JSON with string ID, full_name, and updated_at',
      () {
        final json = {
          'id': 'uuid-123',
          'user_id': 'uuid-123',
          'full_name': 'Full Name',
          'email': 'test@example.com',
          'created_at': '2026-09-01T05:00:00.000Z',
          'updated_at': '2026-09-01T06:00:00.000Z',
        };

        final profile = UserProfile.fromJson(json);

        expect(profile.id, 'uuid-123');
        expect(profile.userId, 'uuid-123');
        expect(profile.fullName, 'Full Name');
        expect(profile.email, 'test@example.com');
        expect(profile.updatedAt, DateTime.parse('2026-09-01T06:00:00.000Z'));
      },
    );
  });

  group('ApiConfig Tests', () {
    test('Generates valid endpoint URLs', () {
      expect(ApiConfig.baseUrl.startsWith('http://'), isTrue);
      expect(ApiConfig.registerEndpoint, endsWith('/api/auth/register'));
      expect(ApiConfig.loginEndpoint, endsWith('/api/auth/login'));
      expect(ApiConfig.profileEndpoint, endsWith('/api/auth/profile'));
    });
  });
}
