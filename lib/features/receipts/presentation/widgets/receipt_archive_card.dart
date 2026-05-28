import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Grid / list cell for a single archived receipt (Sprint 7).
///
/// Two layouts: when [compact] is false (grid) the thumbnail dominates,
/// store name + total stack below; when true (list) it's a horizontal
/// row with leading thumb + 2-line text block + trailing total.
class ReceiptArchiveCard extends StatelessWidget {
  const ReceiptArchiveCard({
    required this.entry,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final ReceiptArchiveEntry entry;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final String store = (entry.storeName ?? '').isEmpty
        ? l.archiveUnknownStore
        : entry.storeName!;
    final String dateStr = DateFormat.yMd(locale).format(entry.date.toLocal());
    final String amount =
        formatMinor(entry.totalMinor, entry.currency, locale: locale);
    return compact
        ? _ListTile(
            entry: entry,
            store: store,
            dateStr: dateStr,
            amount: amount,
            onTap: onTap,
          )
        : _GridTile(
            entry: entry,
            store: store,
            dateStr: dateStr,
            amount: amount,
            onTap: onTap,
          );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.entry,
    required this.store,
    required this.dateStr,
    required this.amount,
    required this.onTap,
  });

  final ReceiptArchiveEntry entry;
  final String store;
  final String dateStr;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('archive.card.${entry.id}'),
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _Thumbnail(imagePath: entry.imagePath),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    store,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    amount,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.entry,
    required this.store,
    required this.dateStr,
    required this.amount,
    required this.onTap,
  });

  final ReceiptArchiveEntry entry;
  final String store;
  final String dateStr;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('archive.card.${entry.id}'),
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _Thumbnail(imagePath: entry.imagePath),
        ),
      ),
      title: Text(store, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(dateStr),
      trailing: Text(amount),
      onTap: onTap,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final String? path = imagePath;
    if (path == null || path.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.receipt_long,
          size: 32,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (BuildContext _, Object _, StackTrace? _) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }
}
