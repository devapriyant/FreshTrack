import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../models/food_item.dart';
import '../providers/food_providers.dart';
import 'add_edit_food_screen.dart';

class FoodInventoryScreen extends ConsumerStatefulWidget {
  const FoodInventoryScreen({super.key});

  @override
  ConsumerState<FoodInventoryScreen> createState() =>
      _FoodInventoryScreenState();
}

class _FoodInventoryScreenState extends ConsumerState<FoodInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getStatusColor(
    BuildContext context,
    FoodExpiryState state,
    String status,
  ) {
    final colors = Theme.of(context).extension<StatusColors>();
    if (status == 'consumed') return colors?.used ?? const Color(0xFF1565C0);
    if (status == 'discarded') return colors?.wasted ?? const Color(0xFF555555);

    switch (state) {
      case FoodExpiryState.expired:
        return colors?.expired ?? const Color(0xFFC62828);
      case FoodExpiryState.expiresToday:
        return colors?.expiresToday ?? const Color(0xFFD84315);
      case FoodExpiryState.expiringSoon:
        return colors?.expiringSoon ?? const Color(0xFFEF6C00);
      case FoodExpiryState.fresh:
        return colors?.fresh ?? const Color(0xFF2E7D32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filterState = ref.watch(foodFilterProvider);
    final filteredItemsAsync = ref.watch(filteredFoodItemsProvider);

    return Scaffold(
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              children: [
                // Search Input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search foods by name, notes...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(foodFilterProvider.notifier)
                                  .setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) {
                    ref.read(foodFilterProvider.notifier).setSearchQuery(val);
                  },
                ),
                const SizedBox(height: 8),

                // Expiry/Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', ExpiryFilter.all, filterState),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Active',
                        ExpiryFilter.active,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Expiring Soon',
                        ExpiryFilter.expiringSoon,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Expires Today',
                        ExpiryFilter.expiresToday,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Fresh',
                        ExpiryFilter.fresh,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Expired',
                        ExpiryFilter.expired,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Consumed',
                        ExpiryFilter.consumed,
                        filterState,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Discarded',
                        ExpiryFilter.discarded,
                        filterState,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(allFoodItemsProvider.notifier).refresh();
              },
              child: filteredItemsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _buildEmptyState(theme, filterState);
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildFoodCard(theme, item);
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, stack) => _buildErrorState(theme, err.toString()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    ExpiryFilter filter,
    FoodFilterState current,
  ) {
    final isSelected = current.filter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        ref.read(foodFilterProvider.notifier).setFilter(filter);
      },
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEmptyState(ThemeData theme, FoodFilterState filterState) {
    final hasFilter =
        filterState.filter != ExpiryFilter.all ||
        filterState.searchQuery.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFilter ? Icons.search_off : Icons.kitchen_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No matching foods found' : 'Your pantry is empty',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try clearing your search query or switching filters.'
                  : 'Start tracking food freshness by adding your first item.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            if (hasFilter)
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  ref.read(foodFilterProvider.notifier).reset();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset Filters'),
              )
            else
              ElevatedButton.icon(
                onPressed: () => _navigateToAdd(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Food Item'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String errorMessage) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load inventory',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(allFoodItemsProvider.notifier).refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodCard(ThemeData theme, FoodItem item) {
    final statusColor = _getStatusColor(context, item.expiryState, item.status);
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Food Name + Quantity + Status Pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.foodName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: item.isConsumed || item.isDiscarded
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (item.category != null && item.category!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            item.category!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Quantity badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'x${item.quantity}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Status/Expiry Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    item.expiryStatusDisplay,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Middle Info Row: Storage location & Expiry Date
            Row(
              children: [
                if (item.storageLocation != null &&
                    item.storageLocation!.isNotEmpty) ...[
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.storageLocation!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Icon(
                  Icons.event_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Expires: ${dateFormat.format(item.expiryDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),

            // Notes if available
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Actions Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Quick Status Buttons
                if (item.isActive) ...[
                  TextButton.icon(
                    onPressed: () => _updateStatus(item, 'consumed'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Used'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _updateStatus(item, 'discarded'),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Discard'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF555555),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: () => _updateStatus(item, 'active'),
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Reactivate'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],

                const Spacer(),

                // Edit Button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit item',
                  onPressed: () => _navigateToEdit(context, item),
                  visualDensity: VisualDensity.compact,
                ),

                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  color: theme.colorScheme.error,
                  tooltip: 'Delete permanently',
                  onPressed: () => _confirmDelete(item),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAdd(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddEditFoodScreen()));
  }

  void _navigateToEdit(BuildContext context, FoodItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddEditFoodScreen(foodItem: item)),
    );
  }

  Future<void> _updateStatus(FoodItem item, String status) async {
    try {
      await ref
          .read(allFoodItemsProvider.notifier)
          .updateStatus(item.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.foodName} marked as $status.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(FoodItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Food Item?'),
        content: Text(
          'Are you sure you want to permanently delete "${item.foodName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(allFoodItemsProvider.notifier).deleteItem(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.foodName} deleted successfully.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete item: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }
}
