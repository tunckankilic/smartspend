import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/core/widgets/placeholder_screen.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.navSettings),
        actions: <Widget>[
          IconButton(
            tooltip: l.authSignOut,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context
                .read<AuthBloc>()
                .add(const AuthSignedOutRequested()),
          ),
        ],
      ),
      body: PlaceholderScreen(
        title: l.navSettings,
        message: l.placeholderSettings,
        icon: Icons.settings_rounded,
      ),
    );
  }
}
