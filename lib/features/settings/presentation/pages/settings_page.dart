import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/constants/app_constants.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/presentation/bloc/export_cubit.dart';
import 'package:smartspend/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Settings shell. Owns no state itself — it provides [SettingsCubit] and
/// [ExportCubit] (cloud-synced prefs + CSV export) and reads the already
/// top-level [AppBloc], [AuthBloc] and [SyncCubit].
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<SettingsCubit>(
          create: (_) => sl<SettingsCubit>()..load(),
        ),
        BlocProvider<ExportCubit>(create: (_) => sl<ExportCubit>()),
      ],
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: MultiBlocListener(
        listeners: <BlocListener<dynamic, dynamic>>[
          BlocListener<ExportCubit, ExportState>(
            listenWhen: (ExportState p, ExportState c) => p.status != c.status,
            listener: _onExportStateChanged,
          ),
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (AuthState p, AuthState c) =>
                c is AuthSignOutPendingConfirmation,
            listener: _onSignOutPending,
          ),
        ],
        child: ListView(
          children: const <Widget>[
            _AccountSection(),
            Divider(height: 1),
            _SyncTile(),
            Divider(height: 1),
            _PreferencesSection(),
            Divider(height: 1),
            _DataSection(),
          ],
        ),
      ),
    );
  }

  Future<void> _onSignOutPending(
    BuildContext context,
    AuthState state,
  ) async {
    if (state is! AuthSignOutPendingConfirmation) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AuthBloc bloc = context.read<AuthBloc>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l.signOutUnsyncedTitle),
          content: Text(l.signOutUnsyncedBody(state.pendingCount)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.signOutUnsyncedCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: Text(l.signOutUnsyncedConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      bloc.add(const AuthSignOutConfirmed());
    } else {
      // Cancelled — the session is still active; re-resolve to return to the
      // authenticated UI.
      bloc.add(const AuthCheckRequested());
    }
  }

  Future<void> _onExportStateChanged(
    BuildContext context,
    ExportState state,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ExportCubit cubit = context.read<ExportCubit>();
    switch (state.status) {
      case ExportStatus.inProgress:
        messenger.showSnackBar(
          SnackBar(content: Text(l.exportPreparing)),
        );
      case ExportStatus.failure:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l.exportFailed)));
        cubit.reset();
      case ExportStatus.success:
        final ExportResultData? data = state.result == null
            ? null
            : ExportResultData(
                url: state.result!.url,
                rowCount: state.result!.rowCount,
              );
        if (data != null) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l.exportReady(data.rowCount))),
            );
          await launchUrl(
            Uri.parse(data.url),
            mode: LaunchMode.externalApplication,
          );
        }
        cubit.reset();
      case ExportStatus.idle:
        break;
    }
  }
}

/// Tiny value holder so the listener can read the result after a null check
/// without juggling `!` operators inline.
class ExportResultData {
  const ExportResultData({required this.url, required this.rowCount});

  final String url;
  final int rowCount;
}

/// A single export action row (CSV or PDF). Shows a spinner when [busy], and
/// is disabled while [anyBusy] so the two exports can't run at once.
class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.anyBusy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: anyBusy ? null : onTap,
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (AuthState p, AuthState c) => c is Authenticated,
      builder: (BuildContext context, AuthState state) {
        final AppUser? user = state is Authenticated ? state.user : null;
        final String display = user?.displayName?.trim().isNotEmpty ?? false
            ? user!.displayName!.trim()
            : (user?.email ?? '');
        final String initial = display.isNotEmpty
            ? display.characters.first.toUpperCase()
            : '?';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(l.settingsAccountSection),
            ListTile(
              leading: CircleAvatar(child: Text(initial)),
              title: Text(
                display.isEmpty ? l.settingsAccountSection : display,
              ),
              subtitle: user?.email == null ? null : Text(user!.email),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(l.authSignOut),
              onTap: () =>
                  context.read<AuthBloc>().add(const AuthSignOutRequested()),
            ),
          ],
        );
      },
    );
  }
}

class _SyncTile extends StatelessWidget {
  const _SyncTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (BuildContext context, SyncState state) {
        final bool inProgress = state is SyncInProgress;
        final String subtitle = switch (state) {
          SyncSynced(:final DateTime? lastSyncAt) when lastSyncAt != null =>
            l.settingsLastSync(_formatTime(context, lastSyncAt)),
          _ => l.settingsLastSyncNever,
        };
        return ListTile(
          leading: const Icon(Icons.sync_rounded),
          title: Text(l.settingsSyncNow),
          subtitle: Text(subtitle),
          trailing: inProgress
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          onTap: inProgress ? null : () => context.read<SyncCubit>().syncNow(),
        );
      },
    );
  }

  String _formatTime(BuildContext context, DateTime utc) {
    final String locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_Hm().format(utc.toLocal());
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeader(l.settingsPreferencesSection),
        BlocBuilder<SettingsCubit, SettingsState>(
          buildWhen: (SettingsState p, SettingsState c) =>
              p.preferences != c.preferences,
          builder: (BuildContext context, SettingsState state) {
            final UserPreferences prefs = state.preferences;
            return Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.payments_rounded),
                  title: Text(l.settingsCurrency),
                  trailing: DropdownButton<String>(
                    value: prefs.currencyCode,
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<String>>[
                      for (final String code in kSupportedCurrencies)
                        DropdownMenuItem<String>(
                          value: code,
                          child: Text(code),
                        ),
                    ],
                    onChanged: (String? code) {
                      if (code != null) {
                        context.read<SettingsCubit>().changeCurrency(code);
                      }
                    },
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_rounded),
                  title: Text(l.settingsNotifications),
                  subtitle: Text(l.settingsNotificationsSubtitle),
                  value: prefs.notificationsEnabled,
                  onChanged: (bool enabled) => context
                      .read<SettingsCubit>()
                      .toggleNotifications(enabled),
                ),
              ],
            );
          },
        ),
        const _LanguageTile(),
        const _DarkModeTile(),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (AppState p, AppState c) => p.locale != c.locale,
      builder: (BuildContext context, AppState state) {
        final String? code = state.locale?.languageCode;
        return ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(l.settingsLanguage),
          trailing: DropdownButton<String?>(
            value: code,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                child: Text(l.settingsLanguageSystem),
              ),
              DropdownMenuItem<String?>(
                value: 'tr',
                child: Text(l.languageTurkish),
              ),
              DropdownMenuItem<String?>(
                value: 'en',
                child: Text(l.languageEnglish),
              ),
              DropdownMenuItem<String?>(
                value: 'de',
                child: Text(l.languageGerman),
              ),
            ],
            onChanged: (String? value) => context.read<AppBloc>().add(
              AppLocaleChanged(value == null ? null : Locale(value)),
            ),
          ),
        );
      },
    );
  }
}

class _DarkModeTile extends StatelessWidget {
  const _DarkModeTile();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (AppState p, AppState c) => p.themeMode != c.themeMode,
      builder: (BuildContext context, AppState state) {
        final bool isDark = state.themeMode == ThemeMode.dark;
        return SwitchListTile(
          secondary: const Icon(Icons.dark_mode_rounded),
          title: Text(l.settingsDarkMode),
          value: isDark,
          onChanged: (bool on) => context.read<AppBloc>().add(
            AppThemeModeChanged(on ? ThemeMode.dark : ThemeMode.light),
          ),
        );
      },
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeader(l.settingsDataSection),
        BlocBuilder<ExportCubit, ExportState>(
          buildWhen: (ExportState p, ExportState c) =>
              p.status != c.status || p.format != c.format,
          builder: (BuildContext context, ExportState state) {
            final bool inProgress = state.status == ExportStatus.inProgress;
            return Column(
              children: <Widget>[
                _ExportTile(
                  icon: Icons.download_rounded,
                  title: l.settingsDownloadData,
                  subtitle: l.settingsDownloadDataSubtitle,
                  busy: inProgress && state.format == ExportFormat.csv,
                  anyBusy: inProgress,
                  onTap: () => context.read<ExportCubit>().exportData(),
                ),
                _ExportTile(
                  icon: Icons.picture_as_pdf_rounded,
                  title: l.settingsDownloadPdf,
                  subtitle: l.settingsDownloadPdfSubtitle,
                  busy: inProgress && state.format == ExportFormat.pdf,
                  anyBusy: inProgress,
                  onTap: () => context
                      .read<ExportCubit>()
                      .exportData(format: ExportFormat.pdf),
                ),
              ],
            );
          },
        ),
        _LegalTile(
          icon: Icons.privacy_tip_outlined,
          title: l.settingsPrivacyPolicy,
          url: AppConstants.privacyPolicyUrl,
        ),
        _LegalTile(
          icon: Icons.description_outlined,
          title: l.settingsTermsOfUse,
          url: AppConstants.termsOfUseUrl,
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_forever_rounded, color: colors.error),
          title: Text(
            l.authDeleteAccount,
            style: TextStyle(color: colors.error),
          ),
          subtitle: Text(l.authDeleteAccountDialogBody),
          isThreeLine: true,
          onTap: () => _confirmDeleteAccount(context, l),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final AuthBloc bloc = context.read<AuthBloc>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l.authDeleteAccountDialogTitle),
          content: Text(l.authDeleteAccountDialogBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.authDeleteAccountCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: Text(l.authDeleteAccountConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      bloc.add(const AuthAccountDeletionRequested());
    }
  }
}

/// Opens a legal document (privacy policy / terms) in the external browser.
/// The URLs live in [AppConstants] — fill the placeholders before release.
class _LegalTile extends StatelessWidget {
  const _LegalTile({
    required this.icon,
    required this.title,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
