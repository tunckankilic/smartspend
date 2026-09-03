import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_profile_wizard_cubit.dart';
import 'package:smartspend/features/taxes/presentation/tax_labels.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Mükellefiyet profili — the eight-question wizard (1.3.0, Block 4b).
///
/// Two entry points: the end of onboarding, and Settings. Every step is
/// skippable and skipping is a first-class outcome, not a failure: an
/// unanswered question stays `unknown`, the generator reports it as a gap,
/// and the calendar screen shows what is missing. A wizard that refused to
/// advance would produce a fuller-looking calendar built on answers the user
/// did not actually give.
///
/// It is also the instrument that answers D-2 — the legal-form distribution
/// — which is why "I'd rather not say" is a visible option rather than
/// something you get by force-quitting.
class TaxProfileWizardPage extends StatelessWidget {
  const TaxProfileWizardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TaxProfileWizardCubit>(
      create: (BuildContext _) => sl<TaxProfileWizardCubit>()..load(),
      child: const _WizardView(),
    );
  }
}

class _WizardView extends StatelessWidget {
  const _WizardView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);

    return BlocConsumer<TaxProfileWizardCubit, TaxProfileWizardState>(
      listenWhen: (TaxProfileWizardState a, TaxProfileWizardState b) =>
          a.status != b.status,
      listener: (BuildContext context, TaxProfileWizardState state) {
        if (state.status == TaxProfileWizardStatus.saved) {
          Navigator.of(context).pop(true);
        }
        if (state.status == TaxProfileWizardStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.taxWizardSaveFailed)),
          );
        }
      },
      builder: (BuildContext context, TaxProfileWizardState state) {
        final TaxProfileWizardCubit cubit =
            context.read<TaxProfileWizardCubit>();
        final bool busy = state.status == TaxProfileWizardStatus.saving;

        return Scaffold(
          appBar: AppBar(title: Text(l.taxWizardTitle)),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                LinearProgressIndicator(
                  key: const Key('tax.wizard.progress'),
                  value: (state.stepIndex + 1) / state.stepCount,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      Text(
                        l.taxWizardStep(state.stepIndex + 1, state.stepCount),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                          color: Theme.of(context).colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        taxWizardQuestion(l, state.step),
                        key: const Key('tax.wizard.question'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (state.stepIndex == 0) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          l.taxWizardIntro,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                            color: Theme.of(context).colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _StepOptions(state: state),
                    ],
                  ),
                ),
                _WizardActions(state: state, busy: busy, cubit: cubit),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The options for the question on screen.
///
/// Three shapes: legal form (seven), a filing frequency (four, because "how
/// often" and "at all" are the same question), and yes/no/unknown. Each list
/// includes its own "not stated" value — skipping via the button and picking
/// "I don't know" store the same thing, and offering both costs nothing.
class _StepOptions extends StatelessWidget {
  const _StepOptions({required this.state});

  final TaxProfileWizardState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TaxProfileWizardCubit cubit = context.read<TaxProfileWizardCubit>();
    final TaxpayerProfile p = state.profile;

    switch (state.step) {
      case TaxWizardStep.legalForm:
        return _Options<TaxpayerLegalForm>(
          values: TaxpayerLegalForm.values,
          selected: p.legalForm,
          label: (TaxpayerLegalForm v) => taxLegalFormLabel(l, v),
          onSelected: (TaxpayerLegalForm v) =>
              cubit.answer(p.copyWith(legalForm: v)),
        );
      case TaxWizardStep.vatLiability:
        return _Options<VatLiability>(
          values: VatLiability.values,
          selected: p.vatLiability,
          label: (VatLiability v) => taxVatLiabilityLabel(l, v),
          onSelected: (VatLiability v) =>
              cubit.answer(p.copyWith(vatLiability: v)),
        );
      case TaxWizardStep.withholdingLiability:
        return _Options<WithholdingLiability>(
          values: WithholdingLiability.values,
          selected: p.withholdingLiability,
          label: (WithholdingLiability v) => taxWithholdingLabel(l, v),
          onSelected: (WithholdingLiability v) =>
              cubit.answer(p.copyWith(withholdingLiability: v)),
        );
      case TaxWizardStep.employsStaff:
        return _AnswerOptions(
          selected: p.employsStaff,
          onSelected: (TaxpayerAnswer v) =>
              cubit.answer(p.copyWith(employsStaff: v)),
        );
      case TaxWizardStep.bagkurInsured:
        return _AnswerOptions(
          selected: p.bagkurInsured,
          onSelected: (TaxpayerAnswer v) =>
              cubit.answer(p.copyWith(bagkurInsured: v)),
        );
      case TaxWizardStep.usesELedger:
        return _AnswerOptions(
          selected: p.usesELedger,
          onSelected: (TaxpayerAnswer v) =>
              cubit.answer(p.copyWith(usesELedger: v)),
        );
      case TaxWizardStep.ownsVehicle:
        return _AnswerOptions(
          selected: p.ownsVehicle,
          onSelected: (TaxpayerAnswer v) =>
              cubit.answer(p.copyWith(ownsVehicle: v)),
        );
      case TaxWizardStep.ownsRealEstate:
        return _AnswerOptions(
          selected: p.ownsRealEstate,
          onSelected: (TaxpayerAnswer v) =>
              cubit.answer(p.copyWith(ownsRealEstate: v)),
        );
    }
  }
}

class _AnswerOptions extends StatelessWidget {
  const _AnswerOptions({required this.selected, required this.onSelected});

  final TaxpayerAnswer selected;
  final ValueChanged<TaxpayerAnswer> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _Options<TaxpayerAnswer>(
      values: TaxpayerAnswer.values,
      selected: selected,
      label: (TaxpayerAnswer v) => taxAnswerLabel(l, v),
      onSelected: onSelected,
    );
  }
}

class _Options<T> extends StatelessWidget {
  const _Options({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: selected,
      onChanged: (T? picked) {
        if (picked != null) {
          onSelected(picked);
        }
      },
      child: Column(
        children: values
            .map(
              (T value) => RadioListTile<T>(
                key: Key('tax.wizard.option.$value'),
                value: value,
                title: Text(label(value)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WizardActions extends StatelessWidget {
  const _WizardActions({
    required this.state,
    required this.busy,
    required this.cubit,
  });

  final TaxProfileWizardState state;
  final bool busy;
  final TaxProfileWizardCubit cubit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: <Widget>[
          if (state.stepIndex > 0)
            TextButton(
              key: const Key('tax.wizard.back'),
              onPressed: busy ? null : cubit.back,
              child: Text(l.taxWizardBack),
            ),
          const Spacer(),
          // Skip is its own button, next to the primary action rather than
          // hidden in a corner. Making it easy is the point: the honest
          // answer to "do you keep books as e-Defter" is often "no idea",
          // and a user who guesses to get past the screen poisons their own
          // calendar.
          TextButton(
            key: const Key('tax.wizard.skip'),
            onPressed: busy
                ? null
                : () => state.isLastStep ? cubit.submit() : cubit.next(),
            child: Text(l.taxWizardSkip),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('tax.wizard.next'),
            onPressed: busy
                ? null
                : () => state.isLastStep ? cubit.submit() : cubit.next(),
            child: Text(
              state.isLastStep ? l.taxWizardFinish : l.taxWizardNext,
            ),
          ),
        ],
      ),
    );
  }
}
