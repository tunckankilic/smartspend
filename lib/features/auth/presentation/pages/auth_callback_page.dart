import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Landing page for the OAuth / magic-link deep-link callback
/// (`site.tunckankilic.smartspend://login-callback`). `supabase_flutter`
/// exchanges the PKCE code and pushes the new session through
/// `onAuthStateChange`; this page just shows a spinner until [AuthBloc]
/// reports [Authenticated], at which point it routes home.
class AuthCallbackPage extends StatelessWidget {
  const AuthCallbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (BuildContext context, AuthState state) {
          if (state is Authenticated) {
            context.go('/');
          }
        },
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(l.authCallbackLoading),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
