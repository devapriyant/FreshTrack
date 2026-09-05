// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'browser_notification_service.dart';

BrowserNotificationService getBrowserNotificationService() =>
    WebBrowserNotificationService();

class WebBrowserNotificationService implements BrowserNotificationService {
  @override
  bool get isSupported => html.Notification.supported;

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return html.Notification.permission == 'granted';
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final status = await html.Notification.requestPermission();
    return status == 'granted';
  }

  @override
  void showNotification({
    required int id,
    required String title,
    required String body,
  }) {
    if (!isSupported || html.Notification.permission != 'granted') return;
    try {
      html.Notification(title, body: body, tag: id.toString());
    } catch (_) {
      // Browser notification failed or blocked
    }
  }
}
