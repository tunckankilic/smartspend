import 'package:bloc/bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Forwards Bloc lifecycle events to Sentry as breadcrumbs.
///
/// Set [Bloc.observer] = `AppBlocObserver()` in `main` so every event,
/// transition, and error shows up on the user's last session report.
///
/// We deliberately do NOT log full state payloads — they can contain PII
/// (user notes, store names). Only runtime types and event names are sent.
class AppBlocObserver extends BlocObserver {
  AppBlocObserver();

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'bloc.event',
        message: '${bloc.runtimeType} ⇠ ${event.runtimeType}',
        level: SentryLevel.info,
      ),
    );
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'bloc.transition',
        message:
            '${bloc.runtimeType}: '
            '${transition.currentState.runtimeType} → '
            '${transition.nextState.runtimeType}',
        level: SentryLevel.info,
      ),
    );
  }

  @override
  void onError(
    BlocBase<dynamic> bloc,
    Object error,
    StackTrace stackTrace,
  ) {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (Scope scope) {
        scope.setTag('bloc', bloc.runtimeType.toString());
      },
    );
    super.onError(bloc, error, stackTrace);
  }
}
