import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>();
    final notifsAsync = ref.watch(notificationsProvider);
    final filteredNotifications = ref.watch(filteredNotificationsProvider);
    final activeFilter = ref.watch(notificationFilterProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount.toString(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: () async {
                try {
                  await ref
                      .read(notificationsProvider.notifier)
                      .markAllAsRead();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All notifications marked as read.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to mark all as read: $e')),
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(notificationsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip(
                  context,
                  ref,
                  label: 'All',
                  filter: NotificationFilter.all,
                  current: activeFilter,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  context,
                  ref,
                  label: 'Unread',
                  filter: NotificationFilter.unread,
                  current: activeFilter,
                  count: unreadCount,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  context,
                  ref,
                  label: 'Expiring Soon',
                  filter: NotificationFilter.expiringSoon,
                  current: activeFilter,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  context,
                  ref,
                  label: 'Today',
                  filter: NotificationFilter.today,
                  current: activeFilter,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  context,
                  ref,
                  label: 'Expired',
                  filter: NotificationFilter.expired,
                  current: activeFilter,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Notification List / States
          Expanded(
            child: notifsAsync.when(
              data: (allItems) {
                if (allItems.isEmpty) {
                  return _buildEmptyState(
                    theme,
                    title: 'No Notifications Yet',
                    message:
                        'Active foods nearing expiry will show alerts here.',
                  );
                }

                if (filteredNotifications.isEmpty) {
                  return _buildEmptyState(
                    theme,
                    title: 'No Matching Notifications',
                    message: 'Try switching your filter to see other alerts.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredNotifications.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filteredNotifications[index];
                      return _buildNotificationCard(
                        context,
                        ref,
                        item,
                        theme,
                        statusColors,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load notifications',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () =>
                            ref.read(notificationsProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required NotificationFilter filter,
    required NotificationFilter current,
    int? count,
  }) {
    final theme = Theme.of(context);
    final isSelected = current == filter;

    return FilterChip(
      selected: isSelected,
      label: Text(count != null && count > 0 ? '$label ($count)' : label),
      onSelected: (_) {
        ref.read(notificationFilterProvider.notifier).state = filter;
      },
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
    ThemeData theme,
    StatusColors? statusColors,
  ) {
    Color typeColor = theme.colorScheme.primary;
    IconData typeIcon = Icons.notifications_outlined;

    if (item.isExpiringSoon) {
      typeColor = statusColors?.expiringSoon ?? Colors.orange;
      typeIcon = Icons.hourglass_bottom;
    } else if (item.isExpiresToday) {
      typeColor = statusColors?.expiresToday ?? Colors.deepOrange;
      typeIcon = Icons.warning_amber_rounded;
    } else if (item.isExpired) {
      typeColor = statusColors?.expired ?? Colors.red;
      typeIcon = Icons.error_outline;
    }

    final formattedExpiry = DateFormat('yyyy-MM-dd').format(item.expiryDate);
    final formattedTime = DateFormat('MMM d, h:mm a').format(item.createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: item.isRead
              ? (theme.brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200)
              : typeColor.withValues(alpha: 0.5),
          width: item.isRead ? 1.0 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: () async {
          if (!item.isRead) {
            await ref.read(notificationsProvider.notifier).markAsRead(item.id);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(typeIcon, color: typeColor, size: 24),
              ),
              const SizedBox(width: 14),

              // Notification Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: item.isRead
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: typeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: item.isRead ? 0.7 : 0.9,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Expiry Date & Timestamp Badges
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: typeColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Expiry: $formattedExpiry',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: typeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formattedTime,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, ref, item.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notification'),
        content: const Text(
          'Are you sure you want to remove this notification?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(notificationsProvider.notifier).deleteNotification(id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete notification: $e')),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(
    ThemeData theme, {
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
