import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Sends a password-reset (PKCE recovery) email.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _awaitingResult = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _awaitingResult = true);
    context.read<AuthBloc>().add(
          AuthPasswordResetRequested(email: _email.text.trim()),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.authForgotPasswordTitle)),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (BuildContext context, AuthState state) {
          if (!_awaitingResult) {
            return;
          }
          if (state is AuthFailure) {
            setState(() => _awaitingResult = false);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(authFailureMessage(l, state.failure))),
              );
          } else if (state is Unauthenticated) {
            setState(() {
              _awaitingResult = false;
              _sent = true;
            });
          }
        },
        builder: (BuildContext context, AuthState state) {
          if (_sent) {
            return _ResetSentView(onBack: () => context.go('/auth/sign-in'));
          }
          final bool busy = state is AuthLoading;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(l.authPasswordResetHint),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: l.authEmailLabel,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (String? v) =>
                          _isValidEmail(v) ? null : l.authEmailInvalid,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.authForgotPasswordCta),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ResetSentView extends StatelessWidget {
  const _ResetSentView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.mark_email_read_outlined, size: 64),
            const SizedBox(height: 24),
            Text(
              l.authPasswordResetSent,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(l.authPasswordResetHint, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onBack,
              child: Text(l.authBackToSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isValidEmail(String? value) {
  if (value == null) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}
