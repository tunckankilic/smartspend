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
import 'package:connectivity_plus/connectivity_plus.dart';

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
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';

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
    ..registerLazySingleton<AuthBloc>(AuthBloc.new)
    // Scan feature (Sprint 2) ---------------------------------------------
    ..registerLazySingleton<CameraDataSource>(CameraDataSourceImpl.new)
    ..registerLazySingleton<Connectivity>(Connectivity.new)
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
      () => ReceiptEditBloc(repository: sl<ScanRepository>()),
    );

  // Feature registrations land here as sprints progress.
}
