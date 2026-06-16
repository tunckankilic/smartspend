part of 'budget_bloc.dart';

/// Outbound states for [BudgetBloc]. Adjective-shaped per CLAUDE.md.
sealed class BudgetState extends Equatable {
  const BudgetState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// No subscribe yet — only state before the page mounts the BLoC.
final class BudgetInitial extends BudgetState {
  const BudgetInitial();
}

/// Streams are open but at least one hasn't ticked yet. Carries the
/// permission flag so the banner can render *immediately* after the
/// cheap `hasPermission` call returns, even while expenses are still
/// loading.
final class BudgetLoading extends BudgetState {
  const BudgetLoading({this.notificationsEnabled = false});

  final bool notificationsEnabled;

  @override
  List<Object?> get props => <Object?>[notificationsEnabled];
}

/// Steady state — both streams have emitted at least once. The UI reads
/// `snapshots` directly. `transientFailure` is set when a write (create
/// / update / delete) failed — the list is still valid because the
/// previous Drift snapshot is intact.
final class BudgetLoaded extends BudgetState {
  const BudgetLoaded({
    required this.snapshots,
    this.notificationsEnabled = false,
    this.transientFailure,
  });

  final List<BudgetSnapshot> snapshots;
  final bool notificationsEnabled;

  /// Most recent write failure, surfaced as a SnackBar in the page.
  /// `null` once the user dismisses or another write succeeds.
  final Failure? transientFailure;

  bool get isEmpty => snapshots.isEmpty;

  /// Snapshot for the general (uncategorised) budget, or `null` if the
  /// user hasn't created one.
  BudgetSnapshot? get general {
    for (final BudgetSnapshot s in snapshots) {
      if (s.isGeneral) return s;
    }
    return null;
  }

  /// All category-targeted snapshots, in stable bloc order.
  List<BudgetSnapshot> get perCategory {
    return <BudgetSnapshot>[
      for (final BudgetSnapshot s in snapshots)
        if (!s.isGeneral) s,
    ];
  }

  BudgetLoaded copyWith({
    List<BudgetSnapshot>? snapshots,
    bool? notificationsEnabled,
    Failure? transientFailure,
    bool clearTransientFailure = false,
  }) {
    return BudgetLoaded(
      snapshots: snapshots ?? this.snapshots,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      transientFailure: clearTransientFailure
          ? null
          : (transientFailure ?? this.transientFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    snapshots,
    notificationsEnabled,
    transientFailure,
  ];
}

/// Terminal stream error. The page renders a retry CTA that dispatches
/// [BudgetSubscribed] again.
final class BudgetError extends BudgetState {
  const BudgetError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
