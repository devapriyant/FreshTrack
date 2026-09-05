class FreshTrackException implements Exception {
  final String message;
  final String? code;

  FreshTrackException(this.message, [this.code]);

  @override
  String toString() => message;
}

class AuthException extends FreshTrackException {
  AuthException(super.message, [super.code]);
}

class DatabaseException extends FreshTrackException {
  DatabaseException(super.message, [super.code]);
}

class NetworkException extends FreshTrackException {
  NetworkException(super.message, [super.code]);
}

class ValidationException extends FreshTrackException {
  ValidationException(super.message, [super.code]);
}

class NotFoundException extends FreshTrackException {
  NotFoundException(super.message, [super.code]);
}
