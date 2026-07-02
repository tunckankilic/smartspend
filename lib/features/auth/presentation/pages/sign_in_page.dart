import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Email + password sign-in, plus Sign in with Apple on iOS.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
            AuthSignInRequested(
              email: _email.text.trim(),
              password: _password.text,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.authSignInTitle)),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (BuildContext context, AuthState state) {
          if (state is AuthFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(authFailureMessage(l, state.failure)),
                ),
              );
          }
        },
        builder: (BuildContext context, AuthState state) {
          final bool busy = state is AuthLoading;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: l.authEmailLabel,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (String? v) => _isValidEmail(v)
                          ? null
                          : l.authEmailInvalid,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      enabled: !busy,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: l.authPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure
                              ? l.a11yShowPassword
                              : l.a11yHidePassword,
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (String? v) => (v == null || v.isEmpty)
                          ? l.authPasswordTooShort
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => context.push('/auth/forgot-password'),
                        child: Text(l.authForgotPasswordLink),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.authSignInCta),
                    ),
                    if (Platform.isIOS) ...<Widget>[
                      const SizedBox(height: 24),
                      // Official HIG-compliant button from sign_in_with_apple
                      // (Apple prefers its own mark/typography over a custom
                      // OutlinedButton — review-safe styling).
                      SignInWithAppleButton(
                        onPressed: busy
                            ? null
                            : () => context
                                .read<AuthBloc>()
                                .add(const AuthAppleRequested()),
                        text: l.authAppleSignInCta,
                        style: Theme.of(context).brightness == Brightness.dark
                            ? SignInWithAppleButtonStyle.white
                            : SignInWithAppleButtonStyle.black,
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed:
                          busy ? null : () => context.push('/auth/sign-up'),
                      child: Text(l.authNoAccount),
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

bool _isValidEmail(String? value) {
  if (value == null) {
    return false;
  }
  final String trimmed = value.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
}
