import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/food_item.dart';
import '../providers/food_providers.dart';

class AddEditFoodScreen extends ConsumerStatefulWidget {
  final FoodItem? foodItem;
  final String? initialFoodName;
  final String? initialCategory;

  const AddEditFoodScreen({
    super.key,
    this.foodItem,
    this.initialFoodName,
    this.initialCategory,
  });

  @override
  ConsumerState<AddEditFoodScreen> createState() => _AddEditFoodScreenState();
}

class _AddEditFoodScreenState extends ConsumerState<AddEditFoodScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _notesController;

  String? _selectedCategory;
  int _quantity = 1;
  String? _selectedStorageLocation;
  DateTime? _purchaseDate;
  late DateTime _expiryDate;
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Dairy',
    'Produce',
    'Meat & Seafood',
    'Bakery',
    'Pantry',
    'Frozen',
    'Beverages',
    'Snacks',
    'Other',
  ];

  final List<String> _storageLocations = [
    'Refrigerator',
    'Freezer',
    'Pantry',
    'Countertop',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.foodItem;

    _nameController = TextEditingController(
      text: item?.foodName ?? widget.initialFoodName ?? '',
    );
    _notesController = TextEditingController(text: item?.notes ?? '');
    _selectedCategory = item?.category ?? widget.initialCategory;
    _quantity = item?.quantity ?? 1;
    _selectedStorageLocation = item?.storageLocation ?? 'Refrigerator';
    _purchaseDate = item?.purchaseDate;

    if (item != null) {
      _expiryDate = item.expiryDate;
    } else {
      // Default expiry date: 7 days from today
      final now = DateTime.now();
      _expiryDate = DateTime(now.year, now.month, now.day + 7);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isEditMode => widget.foodItem != null;

  Future<void> _selectPurchaseDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _purchaseDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: _expiryDate,
    );

    if (picked != null) {
      setState(() {
        _purchaseDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _selectExpiryDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _expiryDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _purchaseDate ?? DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );

    if (picked != null) {
      setState(() {
        _expiryDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _saveFoodItem() async {
    if (!_formKey.currentState!.validate()) return;

    if (_purchaseDate != null && _purchaseDate!.isAfter(_expiryDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Purchase date cannot be after expiry date.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final draft = FoodItem(
        id: widget.foodItem?.id ?? 0,
        userId: widget.foodItem?.userId ?? 0,
        foodName: _nameController.text.trim(),
        category: _selectedCategory,
        quantity: _quantity,
        purchaseDate: _purchaseDate,
        expiryDate: _expiryDate,
        storageLocation: _selectedStorageLocation,
        notes: _notesController.text.trim(),
        createdAt: widget.foodItem?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditMode) {
        final payload = draft.toUpdatePayload();
        await ref
            .read(allFoodItemsProvider.notifier)
            .updateItem(widget.foodItem!.id, payload);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Food item updated successfully.')),
          );
          Navigator.of(context).pop();
        }
      } else {
        final payload = draft.toCreatePayload();
        await ref.read(allFoodItemsProvider.notifier).addItem(payload);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Food item added successfully!')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save item: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Food Item' : 'Add New Food',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Food Name Field
              Text(
                'Food Name *',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Organic Whole Milk',
                  prefixIcon: Icon(Icons.restaurant_menu),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a food name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Category Selector
              Text(
                'Category',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = selected ? cat : null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Quantity Stepper
              Text(
                'Quantity',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _quantity > 1
                        ? () {
                            setState(() {
                              _quantity--;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_quantity',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    onPressed: () {
                      setState(() {
                        _quantity++;
                      });
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Storage Location
              Text(
                'Storage Location',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _storageLocations.map((loc) {
                  final isSelected = _selectedStorageLocation == loc;
                  return ChoiceChip(
                    label: Text(loc),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedStorageLocation = selected ? loc : null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Dates Section: Expiry Date (Required) & Purchase Date (Optional)
              Row(
                children: [
                  // Expiry Date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expiry Date *',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectExpiryDate(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: theme.inputDecorationTheme.fillColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    dateFormat.format(_expiryDate),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Purchase Date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Purchase Date',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_purchaseDate != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _purchaseDate = null;
                                  });
                                },
                                child: Text(
                                  'Clear',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectPurchaseDate(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: theme.inputDecorationTheme.fillColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _purchaseDate != null
                                        ? dateFormat.format(_purchaseDate!)
                                        : 'Select date',
                                    style: TextStyle(
                                      color: _purchaseDate != null
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Notes
              Text(
                'Notes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Opened, keep in airtight container',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),

              // Save Button
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _saveFoodItem,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isEditMode ? 'Update Item' : 'Save Food Item'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
