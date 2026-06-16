import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';

/// Wireframe 06's inline category filter — a horizontally scrolling row
/// of multi-select chips under the period chips. Mirrors (and stays in
/// sync with) the category section of the filter sheet because both
/// mutate the same `ExpenseFilter.categoryIds` set.
class ExpenseCategoryChips extends StatelessWidget {
  const ExpenseCategoryChips({
    required this.categories,
    required this.selectedIds,
    required this.onToggled,
    super.key,
  });

  final List<Category> categories;
  final Set<int> selectedIds;

  /// Called with the category id to add to / remove from the filter.
  final ValueChanged<int> onToggled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (final Category c in categories) ...<Widget>[
            FilterChip(
              key: ValueKey<String>('categoryChip.${c.id}'),
              avatar: Icon(
                iconForCategory(c.icon),
                size: 16,
                color: Color(c.color),
              ),
              label: Text(c.name),
              selected: selectedIds.contains(c.id),
              onSelected: (_) => onToggled(c.id),
            ),
            if (c != categories.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
