import 'package:flutter/material.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Modal multi-select for "who shared this item?" (Sprint 7).
///
/// Returns the new participant-id list, or `null` when the user dismisses
/// the sheet. The page hands the result to `SplitItemAssigned`.
class SplitAssignmentSheet extends StatefulWidget {
  const SplitAssignmentSheet({
    required this.itemName,
    required this.participants,
    required this.selected,
    super.key,
  });

  final String itemName;
  final List<Participant> participants;
  final List<String> selected;

  static Future<List<String>?> show(
    BuildContext context, {
    required String itemName,
    required List<Participant> participants,
    required List<String> selected,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => SplitAssignmentSheet(
        itemName: itemName,
        participants: participants,
        selected: selected,
      ),
    );
  }

  @override
  State<SplitAssignmentSheet> createState() => _SplitAssignmentSheetState();
}

class _SplitAssignmentSheetState extends State<SplitAssignmentSheet> {
  late Set<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.selected.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.itemName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l.splitAssignSheetHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final Participant p in widget.participants)
                    CheckboxListTile(
                      key: Key('split.assign.${p.id}'),
                      value: _picked.contains(p.id),
                      title: Text(p.name),
                      onChanged: (bool? v) {
                        setState(() {
                          if (v ?? false) {
                            _picked.add(p.id);
                          } else {
                            _picked.remove(p.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop<List<String>>(
                      const <String>[],
                    ),
                    child: Text(l.splitAssignClear),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('split.assign.save'),
                    onPressed: () => Navigator.of(context)
                        .pop<List<String>>(_picked.toList()),
                    child: Text(l.splitAssignSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
