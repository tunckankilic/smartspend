import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:smartspend/core/constants/app_constants.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Email + password registration with a strength check, confirmation field,
/// and a Terms / Privacy acceptance gate. On success the user lands on a
/// "check your inbox" screen (email confirmation is enabled server-side).
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _acceptedTerms = false;
  bool _termsError = false;
  bool _awaitingResult = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _openLegal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _submit() {
    final bool formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_acceptedTerms);
    if (!formOk || !_acceptedTerms) {
      return;
    }
    setState(() => _awaitingResult = true);
    context.read<AuthBloc>().add(
          AuthSignUpRequested(
            email: _email.text.trim(),
            password: _password.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.authSignUpTitle)),
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
              _emailSent = true;
            });
          }
        },
        builder: (BuildContext context, AuthState state) {
          if (_emailSent) {
            return _CheckEmailView(email: _email.text.trim());
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
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      enabled: !busy,
                      autofillHints: const <String>[
                        AutofillHints.newPassword,
                      ],
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
                      validator: (String? v) => _passwordError(l, v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: l.authPasswordConfirmLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: (String? v) =>
                          v == _password.text ? null : l.authPasswordMismatch,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acceptedTerms,
                      enabled: !busy,
                      title: Text(l.authTermsLabel),
                      subtitle: _termsError
                          ? Text(
                              l.authTermsRequired,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : null,
                      onChanged: (bool? v) => setState(() {
                        _acceptedTerms = v ?? false;
                        if (_acceptedTerms) {
                          _termsError = false;
                        }
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => _openLegal(
                                    AppConstants.privacyPolicyUrl,
                                  ),
                            child: Text(l.settingsPrivacyPolicy),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => _openLegal(AppConstants.termsOfUseUrl),
                            child: Text(l.settingsTermsOfUse),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.authSignUpCta),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: busy ? null : () => context.pop(),
                      child: Text(l.authHaveAccount),
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

class _CheckEmailView extends StatelessWidget {
  const _CheckEmailView({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.mark_email_unread_outlined, size: 64),
            const SizedBox(height: 24),
            Text(
              l.authSignUpCheckEmailTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.authSignUpCheckEmailBody(email),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.go('/auth/sign-in'),
              child: Text(l.authBackToSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

String? _passwordError(AppLocalizations l, String? value) {
  final String v = value ?? '';
  if (v.length < 8) {
    return l.authPasswordTooShort;
  }
  final bool hasUpper = v.contains(RegExp('[A-Z]'));
  final bool hasDigit = v.contains(RegExp('[0-9]'));
  if (!hasUpper || !hasDigit) {
    return l.authPasswordWeak;
  }
  return null;
}

bool _isValidEmail(String? value) {
  if (value == null) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}
