import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// AppBar status chip for the Drift ⇄ Supabase sync engine (Sprint 8.3).
///
/// Reads [SyncCubit] from the widget tree — never the [SyncService] directly —
/// and renders a compact icon + label reflecting the current [SyncState].
/// Tapping it triggers a manual sync. Designed to live in `AppBar.actions`.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (BuildContext context, SyncState state) {
        return _SyncChip(
          state: state,
          l: l,
          locale: locale,
          onTap: () => context.read<SyncCubit>().syncNow(),
        );
      },
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({
    required this.state,
    required this.l,
    required this.locale,
    required this.onTap,
  });

  final SyncState state;
  final AppLocalizations l;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (state) {
      SyncInProgress() => (Icons.sync, l.syncIndicatorSyncing, scheme.primary),
      SyncOffline() => (Icons.cloud_off, l.syncIndicatorOffline, scheme.error),
      SyncFailed() => (
          Icons.sync_problem,
          l.syncIndicatorFailed,
          scheme.error,
        ),
      SyncConflict() => (
          Icons.merge_type,
          l.syncConflictBanner,
          scheme.tertiary,
        ),
      SyncPending(:final int count) => (
          Icons.cloud_upload_outlined,
          l.syncIndicatorPending(count),
          scheme.tertiary,
        ),
      SyncSynced(lastSyncAt: final DateTime? at) => (
          Icons.cloud_done_outlined,
          l.syncIndicatorSynced(_formatLastSync(at)),
          scheme.primary,
        ),
      SyncIdle() => (
          Icons.cloud_done_outlined,
          l.syncIndicatorSynced(''),
          scheme.primary,
        ),
    };

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  String _formatLastSync(DateTime? at) {
    if (at == null) return '';
    return DateFormat.Hm(locale).format(at.toLocal());
  }
}

/// Full-width strip shown above a page body while the sync engine is offline
/// (Sprint 8.3). Collapses to nothing otherwise so it can be placed
/// unconditionally at the top of a `Column` / body.
class SyncOfflineBanner extends StatelessWidget {
  const SyncOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocBuilder<SyncCubit, SyncState>(
      buildWhen: (SyncState prev, SyncState next) =>
          (prev is SyncOffline) != (next is SyncOffline),
      builder: (BuildContext context, SyncState state) {
        if (state is! SyncOffline) {
          return const SizedBox.shrink();
        }
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_off,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.syncOfflineBanner,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
