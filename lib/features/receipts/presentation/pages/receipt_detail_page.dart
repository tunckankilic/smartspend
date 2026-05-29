import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_detail_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Fiş Detay (Sprint 7).
///
/// Page-scoped bloc, opened from `ReceiptArchivePage`. Sprint 8 will
/// add a signed-URL fallback for `imagePath`; today we render the
/// local cached `File`.
class ReceiptDetailPage extends StatelessWidget {
  const ReceiptDetailPage({required this.receiptId, super.key});

  final int receiptId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiptDetailBloc>(
      create: (BuildContext _) => sl<ReceiptDetailBloc>()
        ..add(ReceiptDetailLoaded(receiptId: receiptId)),
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.receiptDetailTitle)),
      body: BlocConsumer<ReceiptDetailBloc, ReceiptDetailState>(
        listener: (BuildContext ctx, ReceiptDetailState s) {
          if (s is ReceiptDetailReady && s.transientFailure != null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(l.warrantyWriteFailed)),
            );
          }
        },
        builder: (BuildContext ctx, ReceiptDetailState s) {
          return switch (s) {
            ReceiptDetailInitial() ||
            ReceiptDetailLoading() =>
              const Center(child: CircularProgressIndicator()),
            ReceiptDetailError() => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.receiptDetailMissing,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ReceiptDetailReady() => _ReadyBody(state: s),
          };
        },
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.state});

  final ReceiptDetailReady state;

  Future<void> _pickWarranty(BuildContext context) async {
    final ReceiptDetail d = state.detail;
    final DateTime now = DateTime.now();
    final DateTime initial =
        d.warrantyEndDate ?? now.add(const Duration(days: 365));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 10)),
    );
    if (picked == null) return;
    if (!context.mounted) return;
    context
        .read<ReceiptDetailBloc>()
        .add(ReceiptWarrantyChanged(endDate: picked));
  }

  void _clearWarranty(BuildContext context) {
    context
        .read<ReceiptDetailBloc>()
        .add(const ReceiptWarrantyChanged(endDate: null));
  }

  /// Format quantity as int when whole, else two decimals.
  String _qty(double q) =>
      q == q.truncate() ? q.truncate().toString() : q.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final ReceiptDetail d = state.detail;
    final String store = (d.storeName ?? '').isEmpty
        ? l.archiveUnknownStore
        : d.storeName!;
    final String dateStr = DateFormat.yMMMMd(locale).format(d.date.toLocal());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _DetailImage(
          imagePath: d.imagePath,
          signedImageUrl: state.signedImageUrl,
          imageUnavailable: state.imageUnavailable,
        ),
        const SizedBox(height: 16),
        Text(store, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(dateStr, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          formatMinor(d.totalMinor, d.currency, locale: locale),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        _WarrantyCard(
          detail: d,
          locale: locale,
          onPick: () => _pickWarranty(context),
          onClear: () => _clearWarranty(context),
        ),
        const SizedBox(height: 24),
        Text(
          l.receiptDetailItemsLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (d.items.isEmpty)
          Text(
            l.receiptDetailItemsEmpty,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final ReceiptDetailItem item in d.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: Text(
                '${_qty(item.quantity)} × '
                '${formatMinor(
                  item.unitPriceMinor,
                  d.currency,
                  locale: locale,
                )}',
              ),
              trailing: Text(
                formatMinor(item.totalPriceMinor, d.currency, locale: locale),
              ),
            ),
      ],
    );
  }
}

class _DetailImage extends StatelessWidget {
  const _DetailImage({
    required this.imagePath,
    required this.signedImageUrl,
    required this.imageUnavailable,
  });

  final String? imagePath;
  final String? signedImageUrl;
  final bool imageUnavailable;

  @override
  Widget build(BuildContext context) {
    final String? path = imagePath;
    final bool hasLocal =
        path != null && path.isNotEmpty && File(path).existsSync();
    final String? url = signedImageUrl;

    final Widget child;
    if (hasLocal) {
      child = Image.file(
        File(path),
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
            _placeholder(context, broken: true),
      );
    } else if (url != null && url.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url,
        height: 220,
        fit: BoxFit.cover,
        placeholder: (BuildContext _, String _) => Container(
          height: 220,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
        errorWidget: (BuildContext _, String _, Object _) =>
            _placeholder(context, broken: true),
      );
    } else {
      // No local file and no signed URL. If a remote image was expected but
      // could not be resolved, surface the missing-image notice; otherwise
      // this is simply a receipt without an attached image.
      child = _placeholder(context, broken: imageUnavailable);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }

  Widget _placeholder(BuildContext context, {required bool broken}) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      height: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            broken ? Icons.broken_image : Icons.receipt_long,
            size: broken ? 48 : 64,
          ),
          if (broken) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l.storageImageMissing,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _WarrantyCard extends StatelessWidget {
  const _WarrantyCard({
    required this.detail,
    required this.locale,
    required this.onPick,
    required this.onClear,
  });

  final ReceiptDetail detail;
  final String locale;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime? end = detail.warrantyEndDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.warrantySectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l.warrantyReminderHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (end == null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.warrantyAbsent,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('warranty.add'),
                    onPressed: onPick,
                    icon: const Icon(Icons.event),
                    label: Text(l.warrantyAdd),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      DateFormat.yMMMMd(locale).format(end.toLocal()),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    key: const Key('warranty.clear'),
                    onPressed: onClear,
                    child: Text(l.warrantyClear),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: const Key('warranty.change'),
                    onPressed: onPick,
                    child: Text(l.warrantyChange),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
