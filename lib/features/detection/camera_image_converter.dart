import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

img.Image cameraImageToRgb(
  CameraImage cameraImage, {
  int? targetWidth,
  int? targetHeight,
}) {
  final width = targetWidth ?? cameraImage.width;
  final height = targetHeight ?? cameraImage.height;

  if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
    return _convertBgra8888(cameraImage, width, height);
  }
  if (cameraImage.format.group == ImageFormatGroup.yuv420) {
    return _convertYuv420(cameraImage, width, height);
  }
  throw UnsupportedError(
      'Unsupported image format: ${cameraImage.format.group}');
}

img.Image _convertBgra8888(CameraImage image, int width, int height) {
  final out = img.Image(width: width, height: height);
  final bytes = image.planes.first.bytes;
  final xScale = image.width / width;
  final yScale = image.height / height;

  for (var y = 0; y < height; y++) {
    final srcY = (y * yScale).floor();
    final rowOffset = srcY * image.width * 4;
    for (var x = 0; x < width; x++) {
      final srcX = (x * xScale).floor();
      final offset = rowOffset + srcX * 4;
      final b = bytes[offset];
      final g = bytes[offset + 1];
      final r = bytes[offset + 2];
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

img.Image _convertYuv420(CameraImage image, int width, int height) {
  final sourceWidth = image.width;
  final sourceHeight = image.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final out = img.Image(width: width, height: height);

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final xScale = sourceWidth / width;
  final yScale = sourceHeight / height;

  for (var y = 0; y < height; y++) {
    final srcY = (y * yScale).floor();
    final yRowOffset = srcY * yRowStride;
    final uvRowOffset = (srcY >> 1) * uvRowStride;

    for (var x = 0; x < width; x++) {
      final srcX = (x * xScale).floor();
      final yValue = yPlane.bytes[yRowOffset + srcX];
      final uvOffset = uvRowOffset + (srcX >> 1) * uvPixelStride;

      final uValue = uPlane.bytes[uvOffset];
      final vValue = vPlane.bytes[uvOffset];

      final yDouble = yValue.toDouble();
      final uDouble = uValue.toDouble() - 128.0;
      final vDouble = vValue.toDouble() - 128.0;

      var r = (yDouble + 1.402 * vDouble).round();
      var g = (yDouble - 0.344136 * uDouble - 0.714136 * vDouble).round();
      var b = (yDouble + 1.772 * uDouble).round();

      r = math.max(0, math.min(255, r));
      g = math.max(0, math.min(255, g));
      b = math.max(0, math.min(255, b));

      out.setPixelRgb(x, y, r, g, b);
    }
  }

  return out;
}
