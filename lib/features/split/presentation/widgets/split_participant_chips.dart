import 'package:flutter/material.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Participant chip row with an inline "add" affordance (Sprint 7).
///
/// Self-contained — the page only wires `onAdded` / `onRemoved` and
/// rebuilds when the bloc emits a new participant list. The text field
/// resets after each submission so power-users can add a group quickly
/// without lifting their hands.
class SplitParticipantChips extends StatefulWidget {
  const SplitParticipantChips({
    required this.participants,
    required this.onAdded,
    required this.onRemoved,
    super.key,
  });

  final List<Participant> participants;
  final ValueChanged<String> onAdded;
  final ValueChanged<String> onRemoved;

  @override
  State<SplitParticipantChips> createState() => _SplitParticipantChipsState();
}

class _SplitParticipantChipsState extends State<SplitParticipantChips> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onAdded(value);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.splitParticipantsLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('split.participant.input'),
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.splitParticipantHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const Key('split.participant.add'),
              onPressed: _submit,
              child: Text(l.splitParticipantAdd),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.participants.isEmpty)
          Text(
            l.splitParticipantsEmpty,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final Participant p in widget.participants)
                InputChip(
                  key: Key('split.participant.chip.${p.id}'),
                  label: Text(p.name),
                  onDeleted: () => widget.onRemoved(p.id),
                ),
            ],
          ),
      ],
    );
  }
}
