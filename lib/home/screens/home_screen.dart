import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/food/models/food_item.dart';
import '../../features/food/providers/food_providers.dart';
import '../../features/food/screens/add_edit_food_screen.dart';
import '../../features/food/screens/food_inventory_screen.dart';
import '../../features/notifications/providers/notification_providers.dart';
import '../../features/notifications/screens/notification_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<String> _titles = ['Dashboard', 'Inventory', 'Reports', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    ref.watch(foregroundNotificationCoordinatorProvider);

    final List<Widget> pages = [
      _buildDashboard(theme, profileAsync),
      const FoodInventoryScreen(),
      const _StubView(
        title: 'Reports',
        description: 'Weekly & Monthly waste reports coming in Phase 7',
      ),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar:
          _currentIndex ==
              3 // Profile has its own appbar
          ? null
          : AppBar(
              title: Text(
                _titles[_currentIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: theme.colorScheme.onSurface,
              actions: [
                IconButton(
                  icon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(
                      '$unreadCount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  tooltip: 'Notifications',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _currentIndex != 3
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddEditFoodScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Food'),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            )
          : null,
    );
  }

  Widget _buildDashboard(ThemeData theme, AsyncValue<dynamic> profileAsync) {
    final name = profileAsync.when(
      data: (p) => p?.fullName.split(' ').first ?? 'User',
      loading: () => 'User',
      error: (err, stack) => 'User',
    );

    // Dynamic greeting based on current local time
    final hour = DateTime.now().hour;
    String greeting = 'Hello';
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    final stats = ref.watch(foodStatsProvider);
    final useFirstItems = ref.watch(useFirstFoodItemsProvider);
    final statusColors = theme.extension<StatusColors>();

    final freshColor = statusColors?.fresh ?? const Color(0xFF2E7D32);
    final soonColor = statusColors?.expiringSoon ?? const Color(0xFFEF6C00);
    final expiredColor = statusColors?.expired ?? const Color(0xFFC62828);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // Greeting
          Text(
            '$greeting, $name!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep tracking, save food, reduce waste.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Expiry Summary Cards (Horizontal Grid Layout)
          Text(
            'Quick Stats',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _buildStatCard(
                theme,
                'Active Food',
                '${stats.activeCount}',
                Icons.kitchen_outlined,
                theme.colorScheme.primary,
              ),
              _buildStatCard(
                theme,
                'Fresh',
                '${stats.freshCount}',
                Icons.check_circle_outline,
                freshColor,
              ),
              _buildStatCard(
                theme,
                'Expiring Soon',
                '${stats.expiringSoonCount + stats.expiresTodayCount}',
                Icons.warning_amber_outlined,
                soonColor,
              ),
              _buildStatCard(
                theme,
                'Expired',
                '${stats.expiredCount}',
                Icons.error_outline_outlined,
                expiredColor,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Use This First Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Use This First',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (useFirstItems.isNotEmpty)
                TextButton(
                  onPressed: () {
                    ref
                        .read(foodFilterProvider.notifier)
                        .setFilter(ExpiryFilter.expiringSoon);
                    setState(() {
                      _currentIndex = 1; // Switch to Inventory
                    });
                  },
                  child: const Text('View all'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (useFirstItems.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.soup_kitchen_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "You're all clear!",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Nothing needs your immediate attention today.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: useFirstItems.take(3).map((item) {
                return _buildUseFirstItemCard(theme, item, soonColor);
              }).toList(),
            ),

          const SizedBox(height: 24),

          // Quick Add Section
          Text(
            'Quick Add Common Food',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (context, index) {
                final quickFoods = [
                  {'name': 'Milk', 'category': 'Dairy'},
                  {'name': 'Bread', 'category': 'Bakery'},
                  {'name': 'Eggs', 'category': 'Dairy'},
                  {'name': 'Banana', 'category': 'Produce'},
                  {'name': 'Apple', 'category': 'Produce'},
                ];
                final food = quickFoods[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(food['name']!),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddEditFoodScreen(
                            initialFoodName: food['name'],
                            initialCategory: food['category'],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildUseFirstItemCard(
    ThemeData theme,
    FoodItem item,
    Color soonColor,
  ) {
    final dateFormat = DateFormat('MMM d');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: soonColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.priority_high, size: 20, color: soonColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.foodName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.expiryStatusDisplay} (${dateFormat.format(item.expiryDate)})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: soonColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(allFoodItemsProvider.notifier)
                      .updateStatus(item.id, 'consumed');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${item.foodName} marked as consumed!'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update status: $e'),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Mark Used'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String count,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(
                  count,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StubView extends StatelessWidget {
  final String title;
  final String description;

  const _StubView({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
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
