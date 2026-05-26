import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              Icon(
                Icons.savings_rounded,
                size: 96,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                l.onboardingTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () async {
                  await GetIt.I<OnboardingFlagStore>().markComplete();
                  if (!context.mounted) return;
                  context.go('/');
                },
                child: Text(l.onboardingContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
