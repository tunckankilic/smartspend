// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';
import 'package:smartspend/features/taxes/domain/usecases/save_tax_profile.dart';

/// The eight questions, in the order the wizard asks them.
///
/// Ordered so the answers that remove the most from the calendar come first:
/// legal form rules out whole groups of obligations, while "do you own a car"
/// affects one. A user who gives up after three questions has still narrowed
/// the calendar usefully.
enum TaxWizardStep {
  /// Legal form. Also the bucket D-2 is counted in.
  legalForm,

  /// VAT liability and its frequency.
  vatLiability,

  /// Withholding liability and its frequency.
  withholdingLiability,

  /// Employs staff (SGK 4/a employer).
  employsStaff,

  /// Pays Bağ-Kur (4/b) personally.
  bagkurInsured,

  /// Keeps books as e-Defter.
  usesELedger,

  /// Owns a vehicle.
  ownsVehicle,

  /// Owns real estate.
  ownsRealEstate,
}

/// Where the wizard is.
enum TaxProfileWizardStatus {
  /// Answering.
  editing,

  /// Save in flight.
  saving,

  /// Saved; the page pops.
  saved,

  /// Save failed; the page shows [TaxProfileWizardState.failure].
  failure,
}

/// Wizard state: the answers so far and which question is on screen.
class TaxProfileWizardState extends Equatable {
  const TaxProfileWizardState({
    this.profile = TaxpayerProfile.empty,
    this.stepIndex = 0,
    this.status = TaxProfileWizardStatus.editing,
    this.failure,
  });

  /// The answers so far, including the ones still unanswered.
  final TaxpayerProfile profile;

  /// Index into [TaxWizardStep.values].
  final int stepIndex;

  /// Where the wizard is.
  final TaxProfileWizardStatus status;

  /// Why the save failed.
  final Failure? failure;

  /// The question on screen.
  TaxWizardStep get step => TaxWizardStep.values[stepIndex];

  /// Whether this is the last question.
  bool get isLastStep => stepIndex == TaxWizardStep.values.length - 1;

  /// How many questions there are, for the progress indicator.
  int get stepCount => TaxWizardStep.values.length;

  TaxProfileWizardState copyWith({
    TaxpayerProfile? profile,
    int? stepIndex,
    TaxProfileWizardStatus? status,
    Failure? failure,
  }) =>
      TaxProfileWizardState(
        profile: profile ?? this.profile,
        stepIndex: stepIndex ?? this.stepIndex,
        status: status ?? this.status,
        failure: failure ?? this.failure,
      );

  @override
  List<Object?> get props => <Object?>[profile, stepIndex, status, failure];
}

/// Drives the taxpayer-profile wizard.
///
/// Every step is skippable, and skipping is not a failure mode: the wizard is
/// also the instrument that answers D-2, and a form that refuses to advance
/// measures only who tolerates forms. An unanswered question stays `unknown`,
/// which the generator turns into a visible gap rather than a guess.
class TaxProfileWizardCubit extends Cubit<TaxProfileWizardState> {
  TaxProfileWizardCubit({
    required TaxRepository repository,
    required SaveTaxProfileUseCase saveProfile,
  })  : _repository = repository,
        _saveProfile = saveProfile,
        super(const TaxProfileWizardState());

  final TaxRepository _repository;
  final SaveTaxProfileUseCase _saveProfile;

  /// Loads any answers already stored, so reopening the wizard from settings
  /// starts from what the user said last time rather than from blank.
  Future<void> load() async {
    final Either<Failure, TaxpayerProfile> result =
        await _repository.getProfile();
    result.fold(
      (Failure f) => emit(
        state.copyWith(status: TaxProfileWizardStatus.failure, failure: f),
      ),
      (TaxpayerProfile p) => emit(state.copyWith(profile: p)),
    );
  }

  /// Records an answer without advancing — the page advances explicitly, so a
  /// user can change their mind on the step they are on.
  void answer(TaxpayerProfile updated) =>
      emit(state.copyWith(profile: updated));

  /// Moves to the next question, or does nothing on the last one.
  void next() {
    if (!state.isLastStep) {
      emit(state.copyWith(stepIndex: state.stepIndex + 1));
    }
  }

  /// Moves back, or does nothing on the first question.
  void back() {
    if (state.stepIndex > 0) {
      emit(state.copyWith(stepIndex: state.stepIndex - 1));
    }
  }

  /// Saves whatever has been answered and regenerates the calendar.
  ///
  /// Deliberately does not require a complete profile. A partial calendar
  /// generated from three answers is useful; an abandoned wizard is not.
  Future<void> submit() async {
    emit(state.copyWith(status: TaxProfileWizardStatus.saving));
    final Either<Failure, void> result = await _saveProfile(
      SaveTaxProfileParams(profile: state.profile, fromWizard: true),
    );
    result.fold(
      (Failure f) => emit(
        state.copyWith(status: TaxProfileWizardStatus.failure, failure: f),
      ),
      (_) => emit(state.copyWith(status: TaxProfileWizardStatus.saved)),
    );
  }
}
