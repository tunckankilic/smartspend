import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Entry point for the Scan tab.
///
/// Owns the [ScanBloc] for its lifetime — when the user leaves the tab the
/// bloc is closed so partial scans are discarded.
class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScanBloc>(
      create: (_) => sl<ScanBloc>(),
      child: const _ScanView(),
    );
  }
}

class _ScanView extends StatelessWidget {
  const _ScanView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.scanTitle)),
      body: SafeArea(
        child: BlocConsumer<ScanBloc, ScanState>(
          listenWhen: (ScanState p, ScanState n) => p != n,
          listener: (BuildContext context, ScanState state) {
            // OCR succeeded → push the edit screen with the parsed
            // receipt, then reset the bloc so re-entering the tab is
            // clean. We push on the root navigator (configured in
            // GoRouter) so the tab bar is hidden during edit.
            if (state is ScanSuccess) {
              GoRouter.of(context).push('/scan/result', extra: state.receipt);
              context.read<ScanBloc>().add(const ScanReset());
            }
          },
          builder: (BuildContext context, ScanState state) {
            return switch (state) {
              ScanInitial() => const _IntroPanel(),
              ScanProcessing() => const _ProcessingPanel(),
              ImageReady(image: final File img) => _PreviewPanel(image: img),
              // Transitional — the listener above is already routing
              // away from the tab.
              ScanSuccess() => const _ProcessingPanel(),
              ScanEditing() => const _ProcessingPanel(),
              ScanSaved() => const _SavedPanel(),
              ScanError(failure: final Failure f) => _ErrorPanel(failure: f),
            };
          },
        ),
      ),
    );
  }
}

/// Idle landing — explains the flow and offers the two entry points.
class _IntroPanel extends StatelessWidget {
  const _IntroPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ScanBloc bloc = context.read<ScanBloc>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 16),
          Icon(
            Icons.document_scanner_rounded,
            size: 96,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            l.scanIntroHeadline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            l.scanIntroBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => bloc.add(const CameraOpened()),
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(l.scanActionCapture),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => bloc.add(const GalleryOpened()),
            icon: const Icon(Icons.photo_library_rounded),
            label: Text(l.scanActionGallery),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(l.scanProcessing, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l.scanProcessingHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Image is in hand → show it big and offer Scan / Retake.
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.image});

  final File image;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ScanBloc bloc = context.read<ScanBloc>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.file(image, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l.scanPreviewTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l.scanPreviewBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => bloc.add(const ScanStarted()),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(l.scanActionScan),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => bloc.add(const ScanReset()),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.scanActionRetake),
          ),
        ],
      ),
    );
  }
}

class _SavedPanel extends StatelessWidget {
  const _SavedPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ScanBloc bloc = context.read<ScanBloc>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.savings_rounded,
            size: 96,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(l.scanSavedTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            l.scanSavedBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => bloc.add(const ScanReset()),
            child: Text(l.scanActionDone),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ScanBloc bloc = context.read<ScanBloc>();

    final String message = switch (failure) {
      PermissionFailure() => l.scanPermissionDenied,
      _ => l.scanGenericError,
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 96,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(l.scanErrorTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => bloc.add(const ScanReset()),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.scanErrorRetry),
          ),
        ],
      ),
    );
  }
}
