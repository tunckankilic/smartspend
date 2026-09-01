import 'package:equatable/equatable.dart';

import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';

/// Everything the calendar screen needs in one value.
///
/// [gaps] is not decoration. The generator declines to produce items whose
/// recurrence depends on a question the user skipped — guessing would
/// manufacture deadlines — and a screen that dropped those silently would
/// leave the user believing their calendar is complete. They surface as
/// "finish your profile to see these".
class TaxCalendarSnapshot extends Equatable {
  const TaxCalendarSnapshot({
    required this.items,
    required this.gaps,
    required this.profile,
  });

  /// Empty calendar, no profile — what a user who has never opened the wizard
  /// has.
  static const TaxCalendarSnapshot empty = TaxCalendarSnapshot(
    items: <TaxCalendarItem>[],
    gaps: <TaxCalendarGap>[],
    profile: TaxpayerProfile.empty,
  );

  /// The generated and user-created items, earliest period first.
  final List<TaxCalendarItem> items;

  /// What could not be generated, and why.
  final List<TaxCalendarGap> gaps;

  /// The answers the calendar was generated from.
  final TaxpayerProfile profile;

  /// Whether anything is missing, undated or unanswered.
  bool get isPartial =>
      gaps.isNotEmpty ||
      !profile.isComplete ||
      items.any((TaxCalendarItem i) => i.needsDateWarning);

  @override
  List<Object?> get props => <Object?>[items, gaps, profile];
}
