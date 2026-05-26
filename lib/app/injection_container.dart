import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';
import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/daos/budget_dao.dart';
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/database/daos/sync_log_dao.dart';
import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/core/supabase/supabase_client_provider.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';

/// Process-wide service locator. Always inject via [sl] — never construct
/// repositories, datasources, or BLoCs by hand.
final GetIt sl = GetIt.instance;

/// Wire up dependencies. Call from `main` after `Supabase.initialize` so the
/// [SupabaseClient] is ready when downstream registrations resolve.
///
/// `SharedPreferences` is initialised here because the [OnboardingFlagStore]
/// depends on it being available synchronously.
Future<void> configureDependencies() async {
  // Async singletons first ------------------------------------------------
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  sl
    // Core singletons -----------------------------------------------------
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerLazySingleton<OnboardingFlagStore>(
      () => OnboardingFlagStore(sl<SharedPreferences>()),
    )
    ..registerLazySingleton<SupabaseClient>(
      () => SupabaseClientProvider.client,
    )
    ..registerLazySingleton<Logger>(
      () => Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          colors: true,
          printEmojis: false,
        ),
      ),
    )
    // Local database — single instance per app process.
    ..registerLazySingleton<AppDatabase>(AppDatabase.new)
    // DAOs resolve from the same AppDatabase singleton.
    ..registerLazySingleton<ReceiptDao>(() => sl<AppDatabase>().receiptDao)
    ..registerLazySingleton<ExpenseDao>(() => sl<AppDatabase>().expenseDao)
    ..registerLazySingleton<BudgetDao>(() => sl<AppDatabase>().budgetDao)
    ..registerLazySingleton<CategoryDao>(() => sl<AppDatabase>().categoryDao)
    ..registerLazySingleton<SyncLogDao>(() => sl<AppDatabase>().syncLogDao)
    // Top-level BLoCs — kept as singletons so the router can read their
    // state across rebuilds. Feature-scoped BLoCs (ExpenseListBloc, ...)
    // will be `registerFactory` so they get a fresh instance per route.
    ..registerLazySingleton<AppBloc>(AppBloc.new)
    ..registerLazySingleton<AuthBloc>(AuthBloc.new);

  // Feature registrations land here as sprints progress.
}
