import 'browser_notification_service.dart';

BrowserNotificationService getBrowserNotificationService() =>
    StubBrowserNotificationService();

class StubBrowserNotificationService implements BrowserNotificationService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  void showNotification({
    required int id,
    required String title,
    required String body,
  }) {
    // No-op for non-web environments
  }
}
