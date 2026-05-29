// coverage:ignore-file
// camera/image_picker platform-channel wrapper; requires a device, so it is
// mocked at the repository layer instead.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smartspend/core/error/exceptions.dart';

/// Sentinel code emitted when the user backs out of the system camera /
/// gallery picker. Repository implementations translate this into a
/// silent return-to-initial rather than a surfaced error.
const String kCameraCancelledCode = 'cancelled';

/// Wraps the platform image picker so the repository stays decoupled from
/// the `image_picker` and `image` packages.
abstract class CameraDataSource {
  /// Opens the native camera UI. Returns the captured file or throws
  /// [PermissionException] / [CacheException].
  Future<File> captureImage();

  /// Opens the gallery picker. Same error contract as [captureImage].
  Future<File> pickFromGallery();

  /// Light pre-processing pass over a captured image: auto-orient based on
  /// EXIF and bump contrast slightly so OCR has an easier time downstream.
  /// Writes the result next to the input as `*.processed.jpg` and returns
  /// the new file.
  Future<File> preprocessImage(File raw);
}

class CameraDataSourceImpl implements CameraDataSource {
  CameraDataSourceImpl({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Cap the captured image at 2400px on the long edge — anything larger
  /// blows up the Drift cache without helping OCR accuracy.
  static const double _maxEdge = 2400;
  static const int _jpegQuality = 88;

  @override
  Future<File> captureImage() async {
    return _pick(ImageSource.camera);
  }

  @override
  Future<File> pickFromGallery() async {
    return _pick(ImageSource.gallery);
  }

  Future<File> _pick(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: _maxEdge,
        maxHeight: _maxEdge,
        imageQuality: _jpegQuality,
      );
      if (picked == null) {
        // The user backed out — surface a tagged exception that the
        // repository will translate into a silent state reset.
        throw const PermissionException(
          message: 'User cancelled image selection.',
          code: kCameraCancelledCode,
        );
      }
      return File(picked.path);
    } on PermissionException {
      rethrow;
    } on Exception catch (e) {
      // image_picker surfaces platform errors as PlatformException; the
      // 'photo_access_denied' / 'camera_access_denied' codes map to a
      // user-facing permission dialog upstream.
      final String message = e.toString();
      if (message.contains('camera_access_denied') ||
          message.contains('photo_access_denied')) {
        throw PermissionException(message: message);
      }
      throw CacheException(message: 'Image picker failed: $message');
    }
  }

  @override
  Future<File> preprocessImage(File raw) async {
    try {
      final Uint8List bytes = await raw.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const CacheException(message: 'Could not decode captured image.');
      }

      // EXIF rotation → upright bytes; mild contrast lift for receipts.
      final img.Image oriented = img.bakeOrientation(decoded);
      final img.Image boosted = img.adjustColor(
        oriented,
        contrast: 1.08,
        saturation: 0.92,
      );

      final Uint8List jpeg = Uint8List.fromList(
        img.encodeJpg(boosted, quality: _jpegQuality),
      );

      final Directory dir = await getTemporaryDirectory();
      final String filename =
          '${p.basenameWithoutExtension(raw.path)}.processed.jpg';
      final File out = File(p.join(dir.path, filename));
      await out.writeAsBytes(jpeg, flush: true);
      return out;
    } on CacheException {
      rethrow;
    } on Exception catch (e) {
      throw CacheException(message: 'Preprocess failed: $e');
    }
  }
}
