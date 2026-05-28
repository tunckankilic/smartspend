import 'package:flutter/material.dart';

import 'package:smartspend/core/theme/app_colors.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';

/// Maps the [BudgetTone] enum to concrete palette colors.
///
/// Kept in `presentation/` so the domain layer stays Flutter-free; every
/// widget that needs to draw a budget reads through this single function
/// so the palette stays consistent across the card, list tiles, and the
/// circular progress.
Color budgetToneColor(BudgetTone tone, {bool dim = false}) {
  final Color base = switch (tone) {
    BudgetTone.healthy => AppColors.success,
    BudgetTone.warning => AppColors.accent,
    BudgetTone.danger => AppColors.warning,
    BudgetTone.exceeded => AppColors.error,
  };
  if (!dim) return base;
  return base.withValues(alpha: 0.18);
}
