import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:abhi_share/services/image_compression_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageCompressionService Tests', () {
    // Helper to generate test images in memory using the image package
    Uint8List generateTestJpg(int width, int height, {int quality = 95}) {
      final image = img.Image(width: width, height: height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final r = (x * 255 / width).round();
          final g = (y * 255 / height).round();
          final b = ((x + y) * 128 / (width + height)).round();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    test('Vehicle photo: downscales 3000x2000 to max dimension 1920 and reduces file size', () async {
      final raw = generateTestJpg(3000, 2000, quality: 95);
      expect(raw.length, greaterThan(200 * 1024));

      final result = await ImageCompressionService.compressBytes(
        raw,
        fileName: 'vehicle_creta.jpg',
        category: ImageCategory.vehiclePhoto,
      );

      expect(result.isCompressed, isTrue);
      expect(result.width, 1920);
      expect(result.height, 1280); // Preserved aspect ratio 3:2
      expect(result.compressedLength, lessThan(result.originalLength));
      expect(result.reductionPercentage, greaterThan(0));
      expect(result.mimeType, 'image/jpeg');
      expect(result.extension, '.jpg');
      expect(result.outputFileName, 'vehicle_creta.jpg');
    });

    test('RC Document: compresses high-res document with 2048 max dimension and 85 quality', () async {
      final raw = generateTestJpg(2500, 1500, quality: 95); // High-res camera capture of RC document
      final result = await ImageCompressionService.compressBytes(
        raw,
        fileName: 'rc_card.jpg',
        category: ImageCategory.rcDocument,
      );

      expect(result.isCompressed, isTrue);
      expect(result.width, 2048);
      expect(result.height, (1500 * 2048 / 2500).round());
      expect(result.compressedLength, lessThan(result.originalLength));
      expect(result.mimeType, 'image/jpeg');
      expect(result.extension, '.jpg');
      expect(result.outputFileName, 'rc_card.jpg');
    });

    test('Live selfie: downscales portrait image to 1280 max dimension', () async {
      final raw = generateTestJpg(1600, 2400, quality: 92);
      final result = await ImageCompressionService.compressBytes(
        raw,
        fileName: 'driver_selfie.jpg',
        category: ImageCategory.selfie,
      );

      expect(result.isCompressed, isTrue);
      expect(result.height, 1280); // Taller portrait dimension clamped to 1280
      expect(result.width, (1600 * 1280 / 2400).round());
      expect(result.compressedLength, lessThan(result.originalLength));
      expect(result.mimeType, 'image/jpeg');
      expect(result.outputFileName, 'driver_selfie.jpg');
    });

    test('Vehicle photo around 39KB: successfully compresses and reduces file size', () async {
      // Create a test vehicle photo of approximately 39KB (similar to user report)
      final raw39kb = generateTestJpg(900, 600, quality: 88);
      // Verify image is in the 30KB - 50KB range
      expect(raw39kb.length, greaterThan(25 * 1024));
      expect(raw39kb.length, lessThan(60 * 1024));

      final result = await ImageCompressionService.compressBytes(
        raw39kb,
        fileName: 'car_39kb.jpg',
        category: ImageCategory.vehiclePhoto,
      );

      // Verify it is NOT skipped: it is actively compressed and reduced!
      expect(result.isCompressed, isTrue);
      expect(result.compressedLength, lessThan(result.originalLength));
      expect(result.reductionPercentage, greaterThan(0));
      expect(result.mimeType, 'image/jpeg');
    });

    test('Fast-path: skips tiny/empty streams <= 512 bytes', () async {
      final tinyBytes = Uint8List.fromList(List.generate(200, (i) => i));

      final result = await ImageCompressionService.compressBytes(
        tinyBytes,
        fileName: 'empty_icon.jpg',
        category: ImageCategory.general,
      );

      expect(result.isCompressed, isFalse);
      expect(result.compressedLength, equals(result.originalLength));
      expect(result.bytes, equals(tinyBytes));
    });

    test('Fallback safety: invalid or corrupted image bytes return original safely without crashing', () async {
      final invalidBytes = Uint8List.fromList(List.generate(100000, (i) => (i + 1) % 256));

      final result = await ImageCompressionService.compressBytes(
        invalidBytes,
        fileName: 'corrupted.jpg',
        category: ImageCategory.vehiclePhoto,
      );

      expect(result.isCompressed, isFalse);
      expect(result.compressedLength, equals(result.originalLength));
      expect(result.bytes, equals(invalidBytes));
    });

    test('Fallback safety: returns original when recompression would increase file size', () async {
      // Pre-compressed JPEG at quality 65
      final lowQualityJpg = generateTestJpg(2400, 1600, quality: 65);
      expect(lowQualityJpg.length, greaterThan(80 * 1024));

      // Attempting to compress with a higher target quality (e.g. 98) without downscaling or step-down
      final result = await ImageCompressionService.compressBytes(
        lowQualityJpg,
        fileName: 'low_quality.jpg',
        category: ImageCategory.general,
        customConfig: const CompressionConfig(
          maxDimension: 3000, // larger than current dimension, no downscaling
          quality: 98,        // higher quality, producing larger file
          minQuality: 98,     // floor is 98 so no step-down
        ),
      );

      // Verify safe fallback: returns original without bloating the file
      expect(result.isCompressed, isFalse);
      expect(result.compressedLength, equals(result.originalLength));
      expect(result.bytes, equals(lowQualityJpg));
      expect(result.reductionPercentage, 0.0);
    });

    test('XFile integration: compressXFile compresses and converts back to XFile correctly', () async {
      final raw = generateTestJpg(2200, 1400, quality: 95);
      final xFile = XFile.fromData(raw, name: 'car_photo.jpg', path: 'car_photo.jpg', mimeType: 'image/jpeg');

      final result = await ImageCompressionService.compressXFile(
        xFile,
        category: ImageCategory.vehiclePhoto,
      );

      expect(result.isCompressed, isTrue);
      expect(result.width, 1920);

      final outputXFile = result.toXFile();
      expect(outputXFile.name, 'car_photo.jpg');
      expect(outputXFile.mimeType, 'image/jpeg');

      final outputBytes = await outputXFile.readAsBytes();
      expect(outputBytes.length, equals(result.compressedLength));
    });
  });
}
