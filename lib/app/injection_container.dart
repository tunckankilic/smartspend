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
import 'package:smartspend/core/database/daos/sync_dao.dart';
import 'package:smartspend/core/database/daos/sync_log_dao.dart';
import 'package:smartspend/core/database/daos/tag_dao.dart';
import 'package:smartspend/core/database/daos/user_correction_dao.dart';
import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/core/services/recurring_expense_scheduler.dart';
import 'package:smartspend/core/services/sync_remote_data_source.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/services/sync_service_impl.dart';
import 'package:smartspend/core/supabase/supabase_client_provider.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';
import 'package:smartspend/features/auth/data/datasources/supabase_auth_data_source.dart';
import 'package:smartspend/features/auth/data/repositories/supabase_auth_repository_impl.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';
import 'package:smartspend/features/auth/domain/usecases/apple_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/delete_account_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/google_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/categories/data/repositories/category_repository_impl.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';
import 'package:smartspend/features/categories/domain/usecases/create_category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/categorization/data/engines/hybrid_categorization_engine.dart';
import 'package:smartspend/features/categorization/data/engines/keyword_categorization_engine.dart';
import 'package:smartspend/features/categorization/data/engines/tflite_categorization_engine.dart';
import 'package:smartspend/features/categorization/data/repositories/user_correction_repository_impl.dart';
import 'package:smartspend/features/categorization/data/store_database.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/repositories/user_correction_repository.dart';
import 'package:smartspend/features/categorization/domain/usecases/record_user_correction.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_category_for_receipt.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_tags_for_expense.dart';
import 'package:smartspend/features/categorization/presentation/bloc/categorization_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/gemini_ocr_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/hybrid_ocr_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/mlkit_ocr_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/data/repositories/scan_repository_impl.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/domain/usecases/capture_image.dart';
import 'package:smartspend/features/scan/domain/usecases/pick_image.dart';
import 'package:smartspend/features/scan/domain/usecases/scan_receipt.dart';
import 'package:smartspend/features/expenses/data/datasources/expense_local_data_source.dart';
import 'package:smartspend/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/add_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_all_tags.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_by_id.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_summary.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expenses.dart';
import 'package:smartspend/features/expenses/domain/usecases/update_expense.dart';
import 'package:smartspend/features/expenses/presentation/bloc/add_expense_bloc.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_detail_bloc.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_list_bloc.dart';
import 'package:smartspend/features/budget/data/repositories/budget_repository_impl.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/budget/domain/usecases/create_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/delete_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/update_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/watch_budgets.dart';
import 'package:smartspend/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';
import 'package:smartspend/features/receipts/data/repositories/receipt_archive_repository_impl.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';
import 'package:smartspend/features/receipts/domain/usecases/add_warranty.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_image_url.dart';
import 'package:smartspend/features/receipts/domain/usecases/watch_receipt_archive.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_archive_bloc.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_detail_bloc.dart';
import 'package:smartspend/features/split/data/repositories/split_repository_impl.dart';
import 'package:smartspend/features/split/data/share_plus_split_sink.dart';
import 'package:smartspend/features/split/domain/repositories/split_repository.dart';
import 'package:smartspend/features/split/domain/usecases/load_split_session.dart';
import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';
import 'package:smartspend/features/settings/data/datasources/export_remote_data_source.dart';
import 'package:smartspend/features/settings/data/repositories/export_repository_impl.dart';
import 'package:smartspend/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:smartspend/features/settings/domain/repositories/export_repository.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';
import 'package:smartspend/features/settings/domain/usecases/export_data.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_currency.dart';
import 'package:smartspend/features/settings/domain/usecases/set_notifications_enabled.dart';
import 'package:smartspend/features/settings/presentation/bloc/export_cubit.dart';
import 'package:smartspend/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';

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
    ..registerLazySingleton<SyncDao>(() => sl<AppDatabase>().syncDao)
    ..registerLazySingleton<SyncLogDao>(() => sl<AppDatabase>().syncLogDao)
    ..registerLazySingleton<TagDao>(() => sl<AppDatabase>().tagDao)
    ..registerLazySingleton<UserCorrectionDao>(
      () => sl<AppDatabase>().userCorrectionDao,
    )
    ..registerLazySingleton<UserSettingsDao>(
      () => sl<AppDatabase>().userSettingsDao,
    )
    // Local notifications — single shared plugin instance, initialised in
    // main.dart after DI wiring completes.
    ..registerLazySingleton<NotificationService>(
      FlutterLocalNotificationService.new,
    )
    // Recurring expense scheduler — tick()-ed from main.dart after the
    // notification plugin is initialised.
    ..registerLazySingleton<RecurringExpenseScheduler>(
      () => RecurringExpenseSchedulerImpl(
        expenseDao: sl<ExpenseDao>(),
        notifications: sl<NotificationService>(),
        prefs: sl<SharedPreferences>(),
        logger: sl<Logger>(),
      ),
    )
    // Top-level BLoCs — kept as singletons so the router can read their
    // state across rebuilds. Feature-scoped BLoCs (ExpenseListBloc, ...)
    // will be `registerFactory` so they get a fresh instance per route.
    ..registerLazySingleton<AppBloc>(AppBloc.new)
    // Auth feature (Sprint 8.2) -------------------------------------------
    ..registerLazySingleton<SupabaseAuthDataSource>(
      () => SupabaseAuthDataSourceImpl(
        auth: sl<SupabaseClient>().auth,
        functions: sl<SupabaseClient>().functions,
      ),
    )
    ..registerLazySingleton<AuthRepository>(
      () => SupabaseAuthRepositoryImpl(
        dataSource: sl<SupabaseAuthDataSource>(),
      ),
    )
    ..registerLazySingleton<SignInUseCase>(
      () => SignInUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<SignUpUseCase>(
      () => SignUpUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<SignOutUseCase>(
      () => SignOutUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<DeleteAccountUseCase>(
      () => DeleteAccountUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<GoogleSignInUseCase>(
      () => GoogleSignInUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<AppleSignInUseCase>(
      () => AppleSignInUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<ResetPasswordUseCase>(
      () => ResetPasswordUseCase(sl<AuthRepository>()),
    )
    ..registerLazySingleton<AuthBloc>(
      () => AuthBloc(
        authRepository: sl<AuthRepository>(),
        signIn: sl<SignInUseCase>(),
        signUp: sl<SignUpUseCase>(),
        signOut: sl<SignOutUseCase>(),
        deleteAccount: sl<DeleteAccountUseCase>(),
        googleSignIn: sl<GoogleSignInUseCase>(),
        appleSignIn: sl<AppleSignInUseCase>(),
        resetPassword: sl<ResetPasswordUseCase>(),
        database: sl<AppDatabase>(),
      ),
    )
    // Categories feature (Sprint 4 hoist) ---------------------------------
    ..registerLazySingleton<CategoryRepository>(
      () => CategoryRepositoryImpl(categoryDao: sl<CategoryDao>()),
    )
    ..registerLazySingleton<ListCategoriesUseCase>(
      () => ListCategoriesUseCase(sl<CategoryRepository>()),
    )
    ..registerLazySingleton<CreateCategoryUseCase>(
      () => CreateCategoryUseCase(sl<CategoryRepository>()),
    )
    // Categorization feature (Sprint 4) -----------------------------------
    ..registerLazySingleton<StoreDatabase>(
      () => StoreDatabase(bundle: rootBundle),
    )
    ..registerLazySingleton<CategorizationEngine>(
      () => HybridCategorizationEngine(
        keyword: KeywordCategorizationEngine(database: sl<StoreDatabase>()),
        tflite: const TFLiteCategorizationEngine(),
      ),
    )
    ..registerLazySingleton<SuggestCategoryForReceiptUseCase>(
      () => SuggestCategoryForReceiptUseCase(sl<CategorizationEngine>()),
    )
    ..registerLazySingleton<SuggestTagsForExpenseUseCase>(
      () => const SuggestTagsForExpenseUseCase(),
    )
    ..registerLazySingleton<UserCorrectionRepository>(
      () => UserCorrectionRepositoryImpl(dao: sl<UserCorrectionDao>()),
    )
    ..registerLazySingleton<RecordUserCorrectionUseCase>(
      () => RecordUserCorrectionUseCase(
        repository: sl<UserCorrectionRepository>(),
        logger: sl<Logger>(),
      ),
    )
    ..registerFactory<CategorizationBloc>(
      () => CategorizationBloc(
        suggestCategory: sl<SuggestCategoryForReceiptUseCase>(),
        suggestTags: sl<SuggestTagsForExpenseUseCase>(),
        recordCorrection: sl<RecordUserCorrectionUseCase>(),
      ),
    )
    // Scan feature (Sprint 2) ---------------------------------------------
    ..registerLazySingleton<CameraDataSource>(CameraDataSourceImpl.new)
    ..registerLazySingleton<Connectivity>(Connectivity.new)
    // Sync engine + receipt-image storage (Sprint 8.3) -------------------
    ..registerLazySingleton<SupabaseStorageDataSource>(
      () => SupabaseStorageDataSourceImpl(sl<SupabaseClient>()),
    )
    ..registerLazySingleton<SyncRemoteDataSource>(
      () => SupabaseSyncRemoteDataSource(sl<SupabaseClient>()),
    )
    ..registerLazySingleton<SyncService>(
      () => SupabaseSyncServiceImpl(
        database: sl<AppDatabase>(),
        remote: sl<SyncRemoteDataSource>(),
        connectivity: sl<Connectivity>(),
      ),
    )
    // SyncCubit is the presentation owner of the engine — singleton so the
    // AppBar chip, offline banner, and conflict listener share one
    // subscription. Started in `main` after wiring.
    ..registerLazySingleton<SyncCubit>(
      () => SyncCubit(
        service: sl<SyncService>(),
        connectivity: sl<Connectivity>(),
      ),
    )
    // Settings feature (Sprint 8.3) — cloud-synced prefs + CSV export -----
    ..registerLazySingleton<SettingsRepository>(
      () => SettingsRepositoryImpl(dao: sl<UserSettingsDao>()),
    )
    ..registerLazySingleton<GetPreferencesUseCase>(
      () => GetPreferencesUseCase(sl<SettingsRepository>()),
    )
    ..registerLazySingleton<SetCurrencyUseCase>(
      () => SetCurrencyUseCase(sl<SettingsRepository>()),
    )
    ..registerLazySingleton<SetNotificationsEnabledUseCase>(
      () => SetNotificationsEnabledUseCase(sl<SettingsRepository>()),
    )
    ..registerFactory<SettingsCubit>(
      () => SettingsCubit(
        getPreferences: sl<GetPreferencesUseCase>(),
        setCurrency: sl<SetCurrencyUseCase>(),
        setNotifications: sl<SetNotificationsEnabledUseCase>(),
      ),
    )
    ..registerLazySingleton<ExportRemoteDataSource>(
      () => SupabaseExportRemoteDataSource(
        functions: sl<SupabaseClient>().functions,
      ),
    )
    ..registerLazySingleton<ExportRepository>(
      () => ExportRepositoryImpl(sl<ExportRemoteDataSource>()),
    )
    ..registerLazySingleton<ExportDataUseCase>(
      () => ExportDataUseCase(sl<ExportRepository>()),
    )
    ..registerFactory<ExportCubit>(
      () => ExportCubit(exportData: sl<ExportDataUseCase>()),
    )
    // ML Kit + Gemini share the OCRDataSource contract. The hybrid one is
    // what the repository asks for; the others are tagged via instanceName
    // so the hybrid can resolve them.
    ..registerLazySingleton<OCRDataSource>(
      MLKitOCRDataSource.new,
      instanceName: 'mlkit',
    )
    ..registerLazySingleton<OCRDataSource>(
      () => GeminiOCRDataSource(
        functions: sl<SupabaseClient>().functions,
      ),
      instanceName: 'gemini',
    )
    ..registerLazySingleton<OCRDataSource>(
      () => HybridOCRDataSource(
        mlKit: sl<OCRDataSource>(instanceName: 'mlkit'),
        gemini: sl<OCRDataSource>(instanceName: 'gemini'),
        connectivity: sl<Connectivity>(),
        logger: sl<Logger>(),
      ),
    )
    ..registerLazySingleton<ReceiptParser>(ReceiptParser.new)
    ..registerLazySingleton<ScanRepository>(
      () => ScanRepositoryImpl(
        cameraDataSource: sl<CameraDataSource>(),
        ocrDataSource: sl<OCRDataSource>(),
        parser: sl<ReceiptParser>(),
        receiptDao: sl<ReceiptDao>(),
        expenseDao: sl<ExpenseDao>(),
        categoryDao: sl<CategoryDao>(),
        storage: sl<SupabaseStorageDataSource>(),
      ),
    )
    ..registerLazySingleton<CaptureImageUseCase>(
      () => CaptureImageUseCase(sl<ScanRepository>()),
    )
    ..registerLazySingleton<PickImageUseCase>(
      () => PickImageUseCase(sl<ScanRepository>()),
    )
    ..registerLazySingleton<ScanReceiptUseCase>(
      () => ScanReceiptUseCase(sl<ScanRepository>()),
    )
    // ScanBloc is a factory — each visit to the Scan tab gets a fresh
    // state machine so partial scans don't bleed across navigations.
    ..registerFactory<ScanBloc>(
      () => ScanBloc(
        captureImage: sl<CaptureImageUseCase>(),
        pickImage: sl<PickImageUseCase>(),
        scanReceipt: sl<ScanReceiptUseCase>(),
      ),
    )
    // ReceiptEditBloc is also a factory — its lifetime is bound to the
    // /scan/result route, and we want a fresh editable copy each time
    // the user reviews a scan.
    ..registerFactory<ReceiptEditBloc>(
      () => ReceiptEditBloc(
        repository: sl<ScanRepository>(),
        suggestCategory: sl<SuggestCategoryForReceiptUseCase>(),
      ),
    )
    // Expenses feature (Sprint 3.1) -------------------------------------
    ..registerLazySingleton<ExpenseLocalDataSource>(
      () => ExpenseLocalDataSourceImpl(
        expenseDao: sl<ExpenseDao>(),
        categoryDao: sl<CategoryDao>(),
        receiptDao: sl<ReceiptDao>(),
        tagDao: sl<TagDao>(),
      ),
    )
    ..registerLazySingleton<ExpenseRepository>(
      () => ExpenseRepositoryImpl(
        localDataSource: sl<ExpenseLocalDataSource>(),
      ),
    )
    ..registerLazySingleton<GetExpensesUseCase>(
      () => GetExpensesUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<GetExpenseByIdUseCase>(
      () => GetExpenseByIdUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<GetExpenseSummaryUseCase>(
      () => GetExpenseSummaryUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<AddExpenseUseCase>(
      () => AddExpenseUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<UpdateExpenseUseCase>(
      () => UpdateExpenseUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<DeleteExpenseUseCase>(
      () => DeleteExpenseUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<GetAllTagsUseCase>(
      () => GetAllTagsUseCase(sl<ExpenseRepository>()),
    )
    // Page-scoped blocs are factories so re-entry gets a fresh state
    // machine + fresh stream subscription.
    ..registerFactory<ExpenseListBloc>(
      () => ExpenseListBloc(
        repository: sl<ExpenseRepository>(),
        getSummary: sl<GetExpenseSummaryUseCase>(),
        deleteExpense: sl<DeleteExpenseUseCase>(),
      ),
    )
    ..registerFactory<ExpenseDetailBloc>(
      () => ExpenseDetailBloc(
        getExpenseById: sl<GetExpenseByIdUseCase>(),
        deleteExpense: sl<DeleteExpenseUseCase>(),
      ),
    )
    ..registerFactory<AddExpenseBloc>(
      () => AddExpenseBloc(
        addExpense: sl<AddExpenseUseCase>(),
        updateExpense: sl<UpdateExpenseUseCase>(),
        getAllTags: sl<GetAllTagsUseCase>(),
        listCategories: sl<ListCategoriesUseCase>(),
        createCategory: sl<CreateCategoryUseCase>(),
        suggestTags: sl<SuggestTagsForExpenseUseCase>(),
      ),
    )
    // Budget feature (Sprint 6) -----------------------------------------
    ..registerLazySingleton<BudgetRepository>(
      () => BudgetRepositoryImpl(budgetDao: sl<BudgetDao>()),
    )
    ..registerLazySingleton<WatchBudgetsUseCase>(
      () => WatchBudgetsUseCase(sl<BudgetRepository>()),
    )
    ..registerLazySingleton<CreateBudgetUseCase>(
      () => CreateBudgetUseCase(sl<BudgetRepository>()),
    )
    ..registerLazySingleton<UpdateBudgetUseCase>(
      () => UpdateBudgetUseCase(sl<BudgetRepository>()),
    )
    ..registerLazySingleton<DeleteBudgetUseCase>(
      () => DeleteBudgetUseCase(sl<BudgetRepository>()),
    )
    // Page-scoped — fresh stream subscription on every visit so the
    // baseline-establishing behaviour for threshold notifications stays
    // predictable.
    ..registerFactory<BudgetBloc>(
      () => BudgetBloc(
        watchBudgets: sl<WatchBudgetsUseCase>(),
        createBudget: sl<CreateBudgetUseCase>(),
        updateBudget: sl<UpdateBudgetUseCase>(),
        deleteBudget: sl<DeleteBudgetUseCase>(),
        expenseRepository: sl<ExpenseRepository>(),
        listCategories: sl<ListCategoriesUseCase>(),
        notifications: sl<NotificationService>(),
      ),
    )
    // Dashboard feature (Sprint 5) ---------------------------------------
    ..registerLazySingleton<GetDashboardSnapshotUseCase>(
      () => GetDashboardSnapshotUseCase(sl<ExpenseRepository>()),
    )
    ..registerLazySingleton<GetDashboardInsightUseCase>(
      () => const GetDashboardInsightUseCase(),
    )
    ..registerFactory<DashboardBloc>(
      () => DashboardBloc(
        repository: sl<ExpenseRepository>(),
        budgetRepository: sl<BudgetRepository>(),
        getSnapshot: sl<GetDashboardSnapshotUseCase>(),
        listCategories: sl<ListCategoriesUseCase>(),
      ),
    )
    // Split feature (Sprint 7) -------------------------------------------
    ..registerLazySingleton<SplitRepository>(
      () => SplitRepositoryImpl(receiptDao: sl<ReceiptDao>()),
    )
    ..registerLazySingleton<LoadSplitSessionUseCase>(
      () => LoadSplitSessionUseCase(sl<SplitRepository>()),
    )
    ..registerLazySingleton<SplitShareSink>(SharePlusSplitSink.new)
    // SplitBloc is page-scoped — closing the page discards the session.
    ..registerFactory<SplitBloc>(
      () => SplitBloc(
        loadSession: sl<LoadSplitSessionUseCase>(),
        shareSink: sl<SplitShareSink>(),
      ),
    )
    // Receipts feature (Sprint 7) ----------------------------------------
    ..registerLazySingleton<ReceiptArchiveRepository>(
      () => ReceiptArchiveRepositoryImpl(
        receiptDao: sl<ReceiptDao>(),
        storageDataSource: sl<SupabaseStorageDataSource>(),
      ),
    )
    ..registerLazySingleton<WatchReceiptArchiveUseCase>(
      () => WatchReceiptArchiveUseCase(sl<ReceiptArchiveRepository>()),
    )
    ..registerLazySingleton<GetReceiptDetailUseCase>(
      () => GetReceiptDetailUseCase(sl<ReceiptArchiveRepository>()),
    )
    ..registerLazySingleton<GetReceiptImageUrlUseCase>(
      () => GetReceiptImageUrlUseCase(sl<ReceiptArchiveRepository>()),
    )
    ..registerLazySingleton<AddWarrantyUseCase>(
      () => AddWarrantyUseCase(
        repository: sl<ReceiptArchiveRepository>(),
        notifications: sl<NotificationService>(),
      ),
    )
    ..registerFactory<ReceiptArchiveBloc>(
      () => ReceiptArchiveBloc(
        watchArchive: sl<WatchReceiptArchiveUseCase>(),
      ),
    )
    ..registerFactory<ReceiptDetailBloc>(
      () => ReceiptDetailBloc(
        getDetail: sl<GetReceiptDetailUseCase>(),
        addWarranty: sl<AddWarrantyUseCase>(),
        getImageUrl: sl<GetReceiptImageUrlUseCase>(),
      ),
    );

  // Feature registrations land here as sprints progress.
}
