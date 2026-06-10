import 'package:flutter/material.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Chip-input widget for the AddExpense form.
///
/// * Existing tags render as deletable chips above the text field.
/// * Typing then pressing comma / enter / submit dispatches an `onAdd`.
/// * [suggestions] (previously-used tag names) render as outlined chips
///   the user can tap to add quickly.
///
/// The widget is purely presentational — the parent (an
/// `AddExpensePage`) owns the canonical tag list and reconciles
/// add / remove events into bloc dispatches.
class TagInput extends StatefulWidget {
  const TagInput({
    required this.tags,
    required this.suggestions,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final List<String> tags;
  final List<String> suggestions;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final String value = _ctrl.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final Set<String> currentLower = widget.tags
        .map((String t) => t.toLowerCase())
        .toSet();
    final List<String> remainingSuggestions = widget.suggestions
        .where((String s) => !currentLower.contains(s.toLowerCase()))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.tags
                .map(
                  (String t) => InputChip(
                    label: Text(t),
                    onDeleted: () => widget.onRemove(t),
                  ),
                )
                .toList(growable: false),
          ),
        if (widget.tags.isNotEmpty) const SizedBox(height: 4),
        TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l.addExpenseTagsLabel,
            hintText: l.addExpenseTagsHint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: l.a11yAddTag,
              icon: const Icon(Icons.add_rounded),
              onPressed: _commit,
            ),
          ),
          onChanged: (String value) {
            // Auto-commit on comma — matches the prompt's chip-input UX.
            if (value.contains(',')) {
              final String trimmed = value.replaceAll(',', '').trim();
              if (trimmed.isNotEmpty) {
                widget.onAdd(trimmed);
              }
              _ctrl.clear();
            }
          },
          onSubmitted: (_) => _commit(),
        ),
        if (remainingSuggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l.addExpenseTagsSuggestions,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: remainingSuggestions
                .map(
                  (String s) => ActionChip(
                    label: Text(s),
                    avatar: const Icon(Icons.label_outline_rounded, size: 16),
                    onPressed: () => widget.onAdd(s),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
