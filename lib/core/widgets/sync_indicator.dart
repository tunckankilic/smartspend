import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// AppBar status chip for the Drift ⇄ Supabase sync engine (Sprint 8.3).
///
/// Subscribes to [SyncService.watchStatus] and renders a compact icon +
/// label reflecting the current [SyncPhase]. Tapping it triggers a manual
/// sync. Designed to live in an `AppBar.actions` list.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final SyncService service = sl<SyncService>();
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    return StreamBuilder<SyncPhase>(
      stream: service.watchStatus(),
      builder: (BuildContext context, AsyncSnapshot<SyncPhase> snapshot) {
        final SyncPhase phase =
            snapshot.data ?? const SyncPhaseSynced();
        return _SyncChip(
          phase: phase,
          l: l,
          locale: locale,
          onTap: service.sync,
        );
      },
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({
    required this.phase,
    required this.l,
    required this.locale,
    required this.onTap,
  });

  final SyncPhase phase;
  final AppLocalizations l;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (phase) {
      SyncPhaseSyncing() => (
          Icons.sync,
          l.syncIndicatorSyncing,
          scheme.primary,
        ),
      SyncPhaseOffline() => (
          Icons.cloud_off,
          l.syncIndicatorOffline,
          scheme.error,
        ),
      SyncPhasePending(:final int count) => (
          Icons.cloud_upload_outlined,
          l.syncIndicatorPending(count),
          scheme.tertiary,
        ),
      SyncPhaseSynced(lastSyncAt: final DateTime? at) => (
          Icons.cloud_done_outlined,
          l.syncIndicatorSynced(_formatLastSync(at)),
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

/// Full-width strip shown above a page body while the sync engine is in
/// [SyncPhaseOffline] (Sprint 8.3). Collapses to nothing otherwise so it
/// can be placed unconditionally at the top of a `Column` / body.
class SyncOfflineBanner extends StatelessWidget {
  const SyncOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return StreamBuilder<SyncPhase>(
      stream: sl<SyncService>().watchStatus(),
      builder: (BuildContext context, AsyncSnapshot<SyncPhase> snapshot) {
        if (snapshot.data is! SyncPhaseOffline) {
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
