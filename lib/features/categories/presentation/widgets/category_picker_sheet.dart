import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Modal bottom sheet that lets the user pick (or create) a category.
///
/// Returns a [CategoryPickerResult] via [Navigator.pop]:
/// * `CategoryPickerSelected` — user tapped an existing category
/// * `CategoryPickerCreated` — user filled the "new category" form
/// * `null` — user dismissed the sheet
///
/// Hoisted from `features/scan/presentation/widgets/category_picker_sheet`
/// in Sprint 3 so the Expense list/form, Budget, and Scan flows can all
/// share the same picker.
class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    required this.categories,
    required this.allowCreate,
    super.key,
  });

  final List<Category> categories;
  final bool allowCreate;

  static Future<CategoryPickerResult?> show(
    BuildContext context, {
    required List<Category> categories,
    bool allowCreate = true,
  }) {
    return showModalBottomSheet<CategoryPickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => CategoryPickerSheet(
        categories: categories,
        allowCreate: allowCreate,
      ),
    );
  }

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Category> get _filtered {
    if (_query.isEmpty) return widget.categories;
    final String needle = _query.toLowerCase();
    return widget.categories
        .where((Category c) => c.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<Category> filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(l.editPickCategoryTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: l.editPickCategorySearch,
              border: const OutlineInputBorder(),
            ),
            onChanged: (String value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: filtered.length,
              itemBuilder: (BuildContext ctx, int i) {
                final Category cat = filtered[i];
                return _CategoryTile(
                  category: cat,
                  onTap: () => Navigator.of(context).pop(
                    CategoryPickerResult.selected(cat),
                  ),
                );
              },
            ),
          ),
          if (widget.allowCreate) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(l.editPickCategoryAdd),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextEditingController nameCtrl = TextEditingController();

    final String? created = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(l.editNewCategoryTitle),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.editNewCategoryNameLabel,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.editCancel),
            ),
            FilledButton(
              onPressed: () {
                final String value = nameCtrl.text.trim();
                if (value.isEmpty) return;
                Navigator.of(ctx).pop(value);
              },
              child: Text(l.editNewCategoryCreate),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;
    if (created != null && created.isNotEmpty) {
      Navigator.of(context).pop(
        CategoryPickerResult.created(
          name: created,
          icon: 'more_horiz',
          color: 0xFF9E9E9E,
        ),
      );
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = Color(category.color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(iconForCategory(category.icon), color: tint, size: 28),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Result type for the category picker sheet.
sealed class CategoryPickerResult {
  const CategoryPickerResult();

  factory CategoryPickerResult.selected(Category category) =
      CategoryPickerSelected;
  factory CategoryPickerResult.created({
    required String name,
    required String icon,
    required int color,
  }) = CategoryPickerCreated;
}

final class CategoryPickerSelected extends CategoryPickerResult {
  const CategoryPickerSelected(this.category);

  final Category category;
}

final class CategoryPickerCreated extends CategoryPickerResult {
  const CategoryPickerCreated({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final int color;
}
