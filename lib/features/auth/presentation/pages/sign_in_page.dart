import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Placeholder sign-in surface. Real flow lands in Sprint 8.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.authSignInTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Sprint 8: Supabase Auth (Google / Apple / e-posta) buraya gelecek.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () =>
                    context.read<AuthBloc>().add(const AuthStarted()),
                child: Text(l.authSignInTitle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
