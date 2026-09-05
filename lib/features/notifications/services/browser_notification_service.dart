import 'browser_notification_service_stub.dart'
    if (dart.library.html) 'browser_notification_service_web.dart';

abstract class BrowserNotificationService {
  factory BrowserNotificationService() => getBrowserNotificationService();

  bool get isSupported;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  void showNotification({
    required int id,
    required String title,
    required String body,
  });
}
