import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_preferences.dart';
import '../providers/notification_providers.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _initialized = false;
  bool _isSaving = false;

  late bool _notificationsEnabled;
  late bool _browserNotificationsEnabled;
  late Set<int> _reminderDays;
  late String _timezone;
  late int _reminderHour;

  static const List<String> _commonTimezones = [
    'Asia/Kolkata',
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
    'Asia/Tokyo',
    'Asia/Dubai',
    'Australia/Sydney',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notification Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) {
          if (!_initialized) {
            _notificationsEnabled = prefs.notificationsEnabled;
            _browserNotificationsEnabled = prefs.browserNotificationsEnabled;
            _reminderDays = Set<int>.from(prefs.reminderDays);
            _timezone = prefs.timezone;
            _reminderHour = prefs.reminderHour;
            _initialized = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Master Toggle Card
                Card(
                  child: SwitchListTile(
                    title: const Text(
                      'Enable Expiry Reminders',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Receive in-app alerts when food items are approaching or past expiry',
                    ),
                    value: _notificationsEnabled,
                    onChanged: (val) {
                      setState(() {
                        _notificationsEnabled = val;
                      });
                    },
                    secondary: Icon(
                      Icons.notifications_active,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Reminder Days Section
                Opacity(
                  opacity: _notificationsEnabled ? 1.0 : 0.4,
                  child: AbsorbPointer(
                    absorbing: !_notificationsEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reminder Offsets',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Select when you want to receive alerts before items expire:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(
                            children: [
                              _buildOffsetTile(7, '7 days before expiry'),
                              const Divider(height: 1),
                              _buildOffsetTile(3, '3 days before expiry'),
                              const Divider(height: 1),
                              _buildOffsetTile(1, '1 day before (tomorrow)'),
                              const Divider(height: 1),
                              _buildOffsetTile(0, 'On expiry day (today)'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Time & Timezone Section
                        Text(
                          'Delivery Schedule & Timezone',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(
                            children: [
                              // Reminder Hour Dropdown
                              ListTile(
                                leading: const Icon(Icons.access_time),
                                title: const Text('Daily Reminder Hour'),
                                subtitle: const Text(
                                  'Hour when daily reminders are created',
                                ),
                                trailing: DropdownButton<int>(
                                  value: _reminderHour,
                                  underline: const SizedBox(),
                                  items: List.generate(24, (index) {
                                    final period = index >= 12 ? 'PM' : 'AM';
                                    final displayHour = index == 0
                                        ? 12
                                        : (index > 12 ? index - 12 : index);
                                    return DropdownMenuItem<int>(
                                      value: index,
                                      child: Text('$displayHour:00 $period'),
                                    );
                                  }),
                                  onChanged: (newHour) {
                                    if (newHour != null) {
                                      setState(() => _reminderHour = newHour);
                                    }
                                  },
                                ),
                              ),
                              const Divider(height: 1),

                              // Timezone Dropdown
                              ListTile(
                                leading: const Icon(Icons.language),
                                title: const Text('Timezone'),
                                subtitle: Text(_timezone),
                                trailing: DropdownButton<String>(
                                  value: _commonTimezones.contains(_timezone)
                                      ? _timezone
                                      : _commonTimezones.first,
                                  underline: const SizedBox(),
                                  items: _commonTimezones.map((tz) {
                                    return DropdownMenuItem<String>(
                                      value: tz,
                                      child: Text(tz),
                                    );
                                  }).toList(),
                                  onChanged: (newTz) {
                                    if (newTz != null) {
                                      setState(() => _timezone = newTz);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Browser Notifications
                        Text(
                          'Browser Notifications',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: SwitchListTile(
                            title: const Text(
                              'Foreground Browser Notifications',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Display pop-up alerts in your browser while FreshTrack is open',
                            ),
                            value: _browserNotificationsEnabled,
                            onChanged: (val) async {
                              if (val) {
                                final browserService = ref.read(
                                  browserNotificationServiceProvider,
                                );
                                if (!browserService.isSupported) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Browser notifications are not supported on this platform/browser.',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final granted = await browserService
                                    .requestPermission();
                                if (!granted) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Browser notification permission was denied.',
                                        ),
                                      ),
                                    );
                                  }
                                  setState(() {
                                    _browserNotificationsEnabled = false;
                                  });
                                  return;
                                }
                              }
                              setState(() {
                                _browserNotificationsEnabled = val;
                              });
                            },
                            secondary: const Icon(Icons.desktop_windows),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Honest Scope Notice
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Note: Browser notifications function exclusively in the foreground while FreshTrack is active. Background web push when the application is closed is not included in this phase.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Explicit Save Button
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveSettings,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Settings'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Failed to load settings: $err'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(notificationPreferencesProvider.notifier)
                    .refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetTile(int days, String label) {
    final isSelected = _reminderDays.contains(days);
    return CheckboxListTile(
      value: isSelected,
      title: Text(label),
      onChanged: (bool? checked) {
        setState(() {
          if (checked == true) {
            _reminderDays.add(days);
          } else {
            _reminderDays.remove(days);
          }
        });
      },
    );
  }

  Future<void> _saveSettings() async {
    if (_notificationsEnabled && _reminderDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one reminder offset when notifications are enabled.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedPrefs = NotificationPreferences(
        notificationsEnabled: _notificationsEnabled,
        browserNotificationsEnabled: _browserNotificationsEnabled,
        reminderDays: _reminderDays.toList(),
        timezone: _timezone,
        reminderHour: _reminderHour,
      );

      await ref
          .read(notificationPreferencesProvider.notifier)
          .updatePreferences(updatedPrefs);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification settings updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
