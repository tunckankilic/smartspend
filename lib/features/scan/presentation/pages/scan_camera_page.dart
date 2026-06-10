import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// What the in-app camera screen hands back to its caller via
/// `Navigator.pop`.
sealed class ScanCameraResult {
  const ScanCameraResult();
}

/// User pressed the shutter — [image] is the captured photo.
final class ScanCameraCaptured extends ScanCameraResult {
  const ScanCameraCaptured({required this.image});

  final File image;
}

/// User tapped the gallery shortcut — caller should open the picker.
final class ScanCameraGalleryRequested extends ScanCameraResult {
  const ScanCameraGalleryRequested();
}

/// Camera could not be initialized (no permission, no device, plugin
/// error). Caller should fall back to the system camera via
/// `image_picker`, which carries its own permission UX.
final class ScanCameraUnavailable extends ScanCameraResult {
  const ScanCameraUnavailable();
}

/// Full-screen in-app camera per wireframe 02 — live preview with a
/// receipt frame guide, AI badge, tip banner, and gallery / shutter /
/// flash controls.
///
/// Capture-only: OCR is *not* triggered here. The page pops with a
/// [ScanCameraResult] and the Scan tab drives the rest of the flow.
class ScanCameraPage extends StatefulWidget {
  const ScanCameraPage({super.key});

  @override
  State<ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<ScanCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  FlashMode _flashMode = FlashMode.off;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Standard camera plugin lifecycle dance: release the camera when the
    // app goes inactive, re-acquire on resume.
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        _popUnavailable();
        return;
      }
      final CameraDescription back = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException {
      _popUnavailable();
    }
  }

  void _popUnavailable() {
    if (!mounted) return;
    GoRouter.of(context).pop(const ScanCameraUnavailable());
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final XFile shot = await controller.takePicture();
      if (!mounted) return;
      GoRouter.of(context).pop(ScanCameraCaptured(image: File(shot.path)));
    } on CameraException {
      _popUnavailable();
    }
  }

  Future<void> _toggleFlash() async {
    final CameraController? controller = _controller;
    if (controller == null) return;
    final FlashMode next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
    } on CameraException {
      return; // Device has no flash — keep the current mode silently.
    }
    if (mounted) setState(() => _flashMode = next);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final CameraController? controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (controller != null && controller.value.isInitialized)
            Center(child: CameraPreview(controller))
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          _FrameOverlay(hint: l.scanCameraFrameHint),
          SafeArea(
            child: Column(
              children: <Widget>[
                _TopBar(
                  title: l.scanTitle,
                  closeLabel: l.a11yCloseCamera,
                ),
                const Spacer(),
                _AiBadge(label: l.scanCameraAiBadge),
                const SizedBox(height: 12),
                _TipBanner(text: l.scanCameraTip),
                const SizedBox(height: 16),
                _Controls(
                  flashMode: _flashMode,
                  capturing: _capturing,
                  onGallery: () => GoRouter.of(
                    context,
                  ).pop(const ScanCameraGalleryRequested()),
                  onShutter: _capture,
                  onFlash: _toggleFlash,
                  galleryLabel: l.a11yOpenGallery,
                  shutterLabel: l.a11yShutter,
                  flashLabel: l.a11yToggleFlash,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.closeLabel});

  final String title;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: closeLabel,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => GoRouter.of(context).pop(),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Mirror the leading button's width so the title stays centred.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Receipt frame guide — a rounded rectangle centred on the preview with
/// the alignment hint right under it.
class _FrameOverlay extends StatelessWidget {
  const _FrameOverlay({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.78,
          heightFactor: 0.5,
          child: Column(
            children: <Widget>[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hint,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TipBanner extends StatelessWidget {
  const _TipBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lightbulb_outline_rounded, color: cs.onPrimary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.flashMode,
    required this.capturing,
    required this.onGallery,
    required this.onShutter,
    required this.onFlash,
    required this.galleryLabel,
    required this.shutterLabel,
    required this.flashLabel,
  });

  final FlashMode flashMode;
  final bool capturing;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onFlash;
  final String galleryLabel;
  final String shutterLabel;
  final String flashLabel;

  IconData get _flashIcon {
    return switch (flashMode) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always || FlashMode.torch => Icons.flash_on_rounded,
      FlashMode.off => Icons.flash_off_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          tooltip: galleryLabel,
          iconSize: 30,
          icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
          onPressed: onGallery,
        ),
        Semantics(
          label: shutterLabel,
          button: true,
          child: GestureDetector(
            onTap: capturing ? null : onShutter,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white24, width: 6),
              ),
              child: capturing
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : null,
            ),
          ),
        ),
        IconButton(
          tooltip: flashLabel,
          iconSize: 30,
          icon: Icon(_flashIcon, color: Colors.white),
          onPressed: onFlash,
        ),
      ],
    );
  }
}
