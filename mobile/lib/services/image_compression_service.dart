import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Categories of images handled in AbhiShare, each tuned with tailored
/// compression quality, max dimensions, and clarity preservation targets.
enum ImageCategory {
  /// Vehicle photos (cars, bikes) - clear body, badges, and registration plates.
  vehiclePhoto,

  /// Vehicle registration certificates / documents - high resolution for text legibility.
  rcDocument,

  /// Driver verification live selfie - clear facial features for identification.
  selfie,

  /// Profile photos.
  profile,

  /// General / other uploaded photos.
  general,
}

/// Configuration settings for image compression.
class CompressionConfig {
  /// Maximum width or height dimension in pixels.
  final int maxDimension;

  /// JPEG compression quality (1 to 100).
  final int quality;

  /// Minimum quality floor for adaptive step-down compression.
  final int minQuality;

  const CompressionConfig({
    required this.maxDimension,
    required this.quality,
    this.minQuality = 68,
  });

  /// 1920px max dimension, 80% quality.
  /// Preserves clear vehicle paint, body contours, and registration number plates.
  static const vehicle = CompressionConfig(
    maxDimension: 1920,
    quality: 80,
    minQuality: 68,
  );

  /// 2048px max dimension, 85% quality.
  /// Higher resolution and fidelity to guarantee sharp printed text on RC cards.
  static const rcDocument = CompressionConfig(
    maxDimension: 2048,
    quality: 85,
    minQuality: 75,
  );

  /// 1280px max dimension, 82% quality.
  /// Crisp portrait facial details for driver identity verification.
  static const selfie = CompressionConfig(
    maxDimension: 1280,
    quality: 82,
    minQuality: 70,
  );

  /// 1024px max dimension, 82% quality.
  static const profile = CompressionConfig(
    maxDimension: 1024,
    quality: 82,
    minQuality: 70,
  );

  /// 1920px max dimension, 80% quality.
  static const general = CompressionConfig(
    maxDimension: 1920,
    quality: 80,
    minQuality: 68,
  );

  static CompressionConfig forCategory(ImageCategory category) {
    switch (category) {
      case ImageCategory.vehiclePhoto:
        return vehicle;
      case ImageCategory.rcDocument:
        return rcDocument;
      case ImageCategory.selfie:
        return selfie;
      case ImageCategory.profile:
        return profile;
      case ImageCategory.general:
        return general;
    }
  }
}

/// Result of an image compression operation.
class CompressionResult {
  final Uint8List bytes;
  final int originalLength;
  final int compressedLength;
  final int width;
  final int height;
  final String mimeType;
  final String extension;
  final bool isCompressed;
  final String originalFileName;

  const CompressionResult({
    required this.bytes,
    required this.originalLength,
    required this.compressedLength,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.extension,
    required this.isCompressed,
    required this.originalFileName,
  });

  /// Percentage of data reduction achieved (0.0 to 100.0).
  double get reductionPercentage {
    if (originalLength <= 0 || compressedLength >= originalLength) return 0.0;
    return ((originalLength - compressedLength) / originalLength) * 100.0;
  }

  /// Suitable filename for the output image.
  String get outputFileName {
    if (!isCompressed) return originalFileName;
    final dotIdx = originalFileName.lastIndexOf('.');
    if (dotIdx != -1) {
      return '${originalFileName.substring(0, dotIdx)}$extension';
    }
    return '$originalFileName$extension';
  }

  /// Converts the result back into an [XFile] for compatibility with APIs.
  XFile toXFile({String? customPath}) {
    return XFile.fromData(
      bytes,
      name: outputFileName,
      mimeType: mimeType,
      path: customPath ?? outputFileName,
    );
  }
}

/// Internal payload sent to the background isolate.
class _WorkerPayload {
  final Uint8List originalBytes;
  final int maxDimension;
  final int quality;
  final int minQuality;
  final String fileName;

  _WorkerPayload({
    required this.originalBytes,
    required this.maxDimension,
    required this.quality,
    required this.minQuality,
    required this.fileName,
  });
}

/// Dedicated service for performing image compression with minimal quality loss.
/// Executes decoding, EXIF orientation correction, resizing, and encoding inside a background isolate.
class ImageCompressionService {
  ImageCompressionService._();

  /// Compresses an [XFile] using the settings tailored for [category].
  /// Never blocks the UI thread. Gracefully falls back to original if compression fails or increases size.
  static Future<CompressionResult> compressXFile(
    XFile file, {
    ImageCategory category = ImageCategory.general,
    CompressionConfig? customConfig,
  }) async {
    final effectiveName = file.name.isNotEmpty
        ? file.name
        : (file.path.isNotEmpty ? file.path.split(RegExp(r'[/\\]')).last : 'image.jpg');
    try {
      final bytes = await file.readAsBytes();
      return await compressBytes(
        bytes,
        fileName: effectiveName,
        category: category,
        customConfig: customConfig,
      );
    } catch (e, st) {
      developer.log(
        'ImageCompressionService: Failed reading XFile, falling back to original: $e',
        error: e,
        stackTrace: st,
      );
      final fallbackBytes = await file.readAsBytes();
      return CompressionResult(
        bytes: fallbackBytes,
        originalLength: fallbackBytes.length,
        compressedLength: fallbackBytes.length,
        width: 0,
        height: 0,
        mimeType: _guessMimeType(effectiveName),
        extension: _extractExtension(effectiveName),
        isCompressed: false,
        originalFileName: effectiveName,
      );
    }
  }

  /// Compresses raw image bytes using settings for [category].
  static Future<CompressionResult> compressBytes(
    Uint8List originalBytes, {
    required String fileName,
    ImageCategory category = ImageCategory.general,
    CompressionConfig? customConfig,
  }) async {
    final config = customConfig ?? CompressionConfig.forCategory(category);

    // Fast-path: Only skip if file has no readable image payload (<= 512 bytes).
    if (originalBytes.length <= 512) {
      return CompressionResult(
        bytes: originalBytes,
        originalLength: originalBytes.length,
        compressedLength: originalBytes.length,
        width: 0,
        height: 0,
        mimeType: _guessMimeType(fileName),
        extension: _extractExtension(fileName),
        isCompressed: false,
        originalFileName: fileName,
      );
    }

    final payload = _WorkerPayload(
      originalBytes: originalBytes,
      maxDimension: config.maxDimension,
      quality: config.quality,
      minQuality: config.minQuality,
      fileName: fileName,
    );

    // Run in background isolate using compute() to prevent main thread frame drops.
    try {
      final result = await compute(_compressWorker, payload);
      developer.log(
        'ImageCompressionService: ${result.originalFileName} compressed from '
        '${(result.originalLength / 1024).toStringAsFixed(1)}KB to '
        '${(result.compressedLength / 1024).toStringAsFixed(1)}KB '
        '(${result.reductionPercentage.toStringAsFixed(1)}% reduction, isCompressed: ${result.isCompressed})',
      );
      return result;
    } catch (e, st) {
      developer.log(
        'ImageCompressionService: compute error, using fallback: $e',
        error: e,
        stackTrace: st,
      );
      return CompressionResult(
        bytes: originalBytes,
        originalLength: originalBytes.length,
        compressedLength: originalBytes.length,
        width: 0,
        height: 0,
        mimeType: _guessMimeType(fileName),
        extension: _extractExtension(fileName),
        isCompressed: false,
        originalFileName: fileName,
      );
    }
  }
}

/// Top-level worker function running inside background isolate.
CompressionResult _compressWorker(_WorkerPayload payload) {
  final originalBytes = payload.originalBytes;
  final originalLength = originalBytes.length;
  final fileName = payload.fileName;

  try {
    // 1. Decode original image bytes (supports JPEG, PNG, WebP, GIF, etc.)
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      return CompressionResult(
        bytes: originalBytes,
        originalLength: originalLength,
        compressedLength: originalLength,
        width: 0,
        height: 0,
        mimeType: _guessMimeType(fileName),
        extension: _extractExtension(fileName),
        isCompressed: false,
        originalFileName: fileName,
      );
    }

    // 2. Correct EXIF orientation so mobile camera orientation is permanently baked in.
    final oriented = img.bakeOrientation(decoded);

    final currentWidth = oriented.width;
    final currentHeight = oriented.height;

    // 3. Resize proportionally if dimensions exceed maxDimension.
    img.Image resized = oriented;
    if (currentWidth > payload.maxDimension || currentHeight > payload.maxDimension) {
      int targetW;
      int targetH;
      if (currentWidth >= currentHeight) {
        targetW = payload.maxDimension;
        targetH = (currentHeight * payload.maxDimension / currentWidth).round();
      } else {
        targetH = payload.maxDimension;
        targetW = (currentWidth * payload.maxDimension / currentHeight).round();
      }

      resized = img.copyResize(
        oriented,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );
    }

    // 4. Encode to optimized JPEG.
    var currentQuality = payload.quality;
    var compressedList = img.encodeJpg(resized, quality: currentQuality);
    var compressedBytes = Uint8List.fromList(compressedList);

    // If initial pass didn't reduce file size (common when recompressing an already compressed image),
    // perform adaptive step-down on quality and scale if necessary, respecting minQuality.
    if (compressedBytes.length >= originalLength && originalLength > 8 * 1024 && payload.quality > payload.minQuality) {
      final startQ = math.min(68, payload.quality - 5);
      for (int q = startQ; q >= payload.minQuality && compressedBytes.length >= originalLength; q -= 10) {
        final passList = img.encodeJpg(resized, quality: q);
        if (passList.length < originalLength) {
          compressedBytes = Uint8List.fromList(passList);
          break;
        }
      }

      // If still >= originalLength and payload.minQuality < 68, scale dimensions down to achieve target compression
      if (compressedBytes.length >= originalLength && payload.minQuality < 68 && resized.width > 300 && resized.height > 300) {
        final scaled = img.copyResize(
          resized,
          width: (resized.width * 0.82).round(),
          height: (resized.height * 0.82).round(),
          interpolation: img.Interpolation.linear,
        );
        final scaledPass = img.encodeJpg(scaled, quality: payload.minQuality);
        if (scaledPass.length < originalLength) {
          resized = scaled;
          compressedBytes = Uint8List.fromList(scaledPass);
        }
      }
    }

    // 5. Fallback safety: If compressed bytes are empty or still larger than or equal to original, preserve original.
    if (compressedBytes.isEmpty || compressedBytes.length >= originalLength) {
      return CompressionResult(
        bytes: originalBytes,
        originalLength: originalLength,
        compressedLength: originalLength,
        width: currentWidth,
        height: currentHeight,
        mimeType: _guessMimeType(fileName),
        extension: _extractExtension(fileName),
        isCompressed: false,
        originalFileName: fileName,
      );
    }

    // 6. Return successfully compressed result.
    return CompressionResult(
      bytes: compressedBytes,
      originalLength: originalLength,
      compressedLength: compressedBytes.length,
      width: resized.width,
      height: resized.height,
      mimeType: 'image/jpeg',
      extension: '.jpg',
      isCompressed: true,
      originalFileName: fileName,
    );
  } catch (_) {
    // Graceful fallback on any decoding/encoding anomaly.
    return CompressionResult(
      bytes: originalBytes,
      originalLength: originalLength,
      compressedLength: originalLength,
      width: 0,
      height: 0,
      mimeType: _guessMimeType(fileName),
      extension: _extractExtension(fileName),
      isCompressed: false,
      originalFileName: fileName,
    );
  }
}

String _guessMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg';
}

String _extractExtension(String fileName) {
  final idx = fileName.lastIndexOf('.');
  if (idx != -1) {
    return fileName.substring(idx).toLowerCase();
  }
  return '.jpg';
}
