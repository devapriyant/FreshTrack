class NotificationPreferences {
  final bool notificationsEnabled;
  final bool browserNotificationsEnabled;
  final List<int> reminderDays;
  final String timezone;
  final int reminderHour;

  const NotificationPreferences({
    this.notificationsEnabled = true,
    this.browserNotificationsEnabled = false,
    this.reminderDays = const [7, 3, 1, 0],
    this.timezone = 'Asia/Kolkata',
    this.reminderHour = 9,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    List<int> parsedDays = [7, 3, 1, 0];
    if (json['reminder_days'] != null) {
      final rawList = json['reminder_days'];
      if (rawList is List) {
        parsedDays =
            rawList.map((e) => int.tryParse(e.toString()) ?? 0).toSet().toList()
              ..sort((a, b) => b - a);
      }
    }

    return NotificationPreferences(
      notificationsEnabled:
          json['notifications_enabled'] == true ||
          json['notificationsEnabled'] == true,
      browserNotificationsEnabled:
          json['browser_notifications_enabled'] == true ||
          json['browserNotificationsEnabled'] == true,
      reminderDays: parsedDays.isNotEmpty ? parsedDays : const [7, 3, 1, 0],
      timezone: (json['timezone'] ?? 'Asia/Kolkata').toString(),
      reminderHour:
          int.tryParse(
            (json['reminder_hour'] ?? json['reminderHour'] ?? 9).toString(),
          ) ??
          9,
    );
  }

  NotificationPreferences copyWith({
    bool? notificationsEnabled,
    bool? browserNotificationsEnabled,
    List<int>? reminderDays,
    String? timezone,
    int? reminderHour,
  }) {
    return NotificationPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      browserNotificationsEnabled:
          browserNotificationsEnabled ?? this.browserNotificationsEnabled,
      reminderDays: reminderDays ?? this.reminderDays,
      timezone: timezone ?? this.timezone,
      reminderHour: reminderHour ?? this.reminderHour,
    );
  }

  /// Returns payload for PUT /api/notification-preferences.
  /// Never includes user_id or userId.
  Map<String, dynamic> toUpdatePayload() {
    final sortedDays = List<int>.from(reminderDays.toSet())
      ..sort((a, b) => b - a);
    return {
      'notifications_enabled': notificationsEnabled,
      'browser_notifications_enabled': browserNotificationsEnabled,
      'reminder_days': sortedDays,
      'timezone': timezone.trim(),
      'reminder_hour': reminderHour,
    };
  }
}
