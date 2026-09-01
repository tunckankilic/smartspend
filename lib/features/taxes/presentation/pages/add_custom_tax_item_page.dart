import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/taxes/domain/usecases/add_custom_tax_item.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Adds a deadline the user tracks themselves (Block 4b, T9).
///
/// The third of the three signals about whether the generated calendar fits:
/// dismissals say we produced something wrong, edits say we produced
/// something nearly right, and this says we missed something entirely. That
/// is why it is a first-class button on the calendar rather than buried in a
/// menu — a user who cannot add their own item just stops using the screen,
/// and we learn nothing.
///
/// A custom item's date is the user's own claim, so it carries no "unverified"
/// hedge. We are not guessing on their behalf here.
class AddCustomTaxItemPage extends StatefulWidget {
  const AddCustomTaxItemPage({super.key});

  @override
  State<AddCustomTaxItemPage> createState() => _AddCustomTaxItemPageState();
}

class _AddCustomTaxItemPageState extends State<AddCustomTaxItemPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _dueDate = DateTime.now();
  bool _isPayment = true;
  bool _saving = false;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = l.taxCustomNameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _titleError = null;
    });

    final Either<Failure, int> result = await sl<AddCustomTaxItemUseCase>()(
      AddCustomTaxItemParams(
        title: _title.text,
        // Pinned to UTC midnight: the deadline is a calendar day, and letting
        // the device timezone carry it can move it by one.
        dueDate: DateTime.utc(_dueDate.year, _dueDate.month, _dueDate.day),
        isPayment: _isPayment,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );

    if (!mounted) {
      return;
    }
    result.fold(
      (Failure failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.taxDetailSaveFailed)),
        );
      },
      (_) => Navigator.of(context).pop(true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(title: Text(l.taxCustomTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('tax.custom.title'),
            controller: _title,
            decoration: InputDecoration(
              labelText: l.taxCustomName,
              errorText: _titleError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Which deadline this is, because the row keeps filing and payment
          // in separate columns and a custom item has to pick one.
          SegmentedButton<bool>(
            key: const Key('tax.custom.kind'),
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: true,
                label: Text(l.taxCustomKindPayment),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text(l.taxCustomKindDeclaration),
              ),
            ],
            selected: <bool>{_isPayment},
            showSelectedIcon: false,
            onSelectionChanged: (Set<bool> picked) =>
                setState(() => _isPayment = picked.first),
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const Key('tax.custom.date'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(l.taxCustomDueDate),
            subtitle: Text(DateFormat.yMMMd(locale).format(_dueDate)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('tax.custom.note'),
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l.taxDetailNote,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('tax.custom.save'),
            onPressed: _saving ? null : _save,
            child: Text(l.taxCustomSave),
          ),
        ],
      ),
    );
  }
}
