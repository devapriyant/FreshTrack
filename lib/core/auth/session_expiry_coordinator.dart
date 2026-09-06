/// Pure abstract interface for authoritative session expiry.
/// Contains ZERO feature dependencies and ZERO provider definitions,
/// ensuring a clean unidirectional architectural hierarchy.
abstract class SessionExpiryCoordinator {
  /// Atomically revokes credentials, clears user-scoped state,
  /// advances the session epoch, and redirects to authentication.
  Future<void> expireSession();
}
