import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator/palette_generator.dart';

class ExtractedColor {
  final String name;
  final String hex;
  final Color color;

  ExtractedColor(this.name, this.hex, this.color);
}

Color _hexToColor(String hex) {
  final cleaned = hex.replaceAll('#', '').padLeft(6, '0');
  return Color(int.parse('FF$cleaned', radix: 16));
}

String mapColorNameToHex(String name) {
  switch (name) {
    case 'Red':
      return '#E53935';
    case 'Orange':
      return '#FB8C00';
    case 'Yellow':
      return '#FDD835';
    case 'Lime':
      return '#AEEA00';
    case 'Green':
      return '#43A047';
    case 'Cyan':
      return '#00ACC1';
    case 'Blue':
      return '#1E88E5';
    case 'Indigo':
      return '#3949AB';
    case 'Purple':
      return '#8E24AA';
    case 'Pink':
      return '#D81B60';
    case 'Brown':
      return '#8D6E63';
    case 'Black':
      return '#000000';
    case 'White':
      return '#FFFFFF';
    case 'Gray':
    default:
      return '#9E9E9E';
  }
}

String _rgbToColorName(int r, int g, int b) {
  final rf = r / 255.0;
  final gf = g / 255.0;
  final bf = b / 255.0;

  final max = [rf, gf, bf].reduce(math.max);
  final min = [rf, gf, bf].reduce(math.min);
  final delta = max - min;
  final value = max;
  final saturation = max == 0 ? 0.0 : delta / max;

  if (value < 0.16) return 'Black';
  if (saturation < 0.18) {
    if (value > 0.88) return 'White';
    return 'Gray';
  }

  final hue = delta == 0 ? 0.0 : (60.0 * (((gf - bf) / delta) % 6)).abs();

  if (hue < 18 || hue >= 345) return 'Red';
  if (hue < 40) return 'Orange';
  if (hue < 62) return 'Yellow';
  if (hue < 95) return 'Lime';
  if (hue < 150) return 'Green';
  if (hue < 185) return 'Cyan';
  if (hue < 220) return 'Blue';
  if (hue < 265) return 'Indigo';
  if (hue < 305) return 'Purple';
  if (hue < 345) return 'Pink';

  if (r > g && g > b && value < 0.72 && saturation > 0.35) {
    return 'Brown';
  }

  return 'Gray';
}

String _colorNameToHex(String name) {
  return mapColorNameToHex(name);
}

ExtractedColor mapRgbToNearestPalette(int r, int g, int b) {
  final name = _rgbToColorName(r, g, b);
  final hex = _colorNameToHex(name);
  return ExtractedColor(name, hex, _hexToColor(hex));
}

List<ExtractedColor> extractColorTagsFromRegion(img.Image image, Rect normalizedRect,
    {int maxTags = 3}) {
  final insetX = normalizedRect.width * 0.18;
  final insetY = normalizedRect.height * 0.18;
  final cropped = Rect.fromLTRB(
    (normalizedRect.left + insetX).clamp(0.0, 1.0),
    (normalizedRect.top + insetY).clamp(0.0, 1.0),
    (normalizedRect.right - insetX).clamp(0.0, 1.0),
    (normalizedRect.bottom - insetY).clamp(0.0, 1.0),
  );

  final left = (cropped.left * image.width).floor().clamp(0, image.width - 1);
  final top = (cropped.top * image.height).floor().clamp(0, image.height - 1);
  final right = (cropped.right * image.width).ceil().clamp(1, image.width);
  final bottom = (cropped.bottom * image.height).ceil().clamp(1, image.height);

  if (right <= left || bottom <= top) return const [];

  final counts = <String, double>{};
  final xStep = math.max(1, ((right - left) / 24).floor()).toInt();
  final yStep = math.max(1, ((bottom - top) / 24).floor()).toInt();

  for (var y = top; y < bottom; y += yStep) {
    for (var x = left; x < right; x += xStep) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final maxChannel = [r, g, b].reduce(math.max);
      final minChannel = [r, g, b].reduce(math.min);
      final saturation =
          maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;
      final name = _rgbToColorName(r, g, b);

      if (saturation < 0.12 &&
          (name == 'Gray' || name == 'White' || name == 'Black')) {
        continue;
      }

      final weight = saturation >= 0.18 ? 1.0 + saturation : 0.4;
      counts[name] = (counts[name] ?? 0) + weight;
    }
  }

  if (counts.isEmpty) {
    final dominant = extractDominantColorFromImage(image);
    return dominant == null ? const [] : [dominant];
  }

  final ordered = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return ordered
      .take(maxTags)
      .map((entry) => ExtractedColor(
            entry.key,
            mapColorNameToHex(entry.key),
            _hexToColor(mapColorNameToHex(entry.key)),
          ))
      .toList(growable: false);
}

ExtractedColor? extractDominantColorFromImage(img.Image image) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;

  final xStep = math.max(1, (image.width / 40).floor()).toInt();
  final yStep = math.max(1, (image.height / 40).floor()).toInt();

  for (var y = 0; y < image.height; y += yStep) {
    for (var x = 0; x < image.width; x += xStep) {
      final p = image.getPixel(x, y);
      red += p.r.toInt();
      green += p.g.toInt();
      blue += p.b.toInt();
      count++;
    }
  }

  if (count == 0) return null;
  return mapRgbToNearestPalette(red ~/ count, green ~/ count, blue ~/ count);
}

ExtractedColor? extractAverageColorFromRegion(
    img.Image image, Rect normalizedRect) {
  final insetX = normalizedRect.width * 0.18;
  final insetY = normalizedRect.height * 0.18;
  final cropped = Rect.fromLTRB(
    (normalizedRect.left + insetX).clamp(0.0, 1.0),
    (normalizedRect.top + insetY).clamp(0.0, 1.0),
    (normalizedRect.right - insetX).clamp(0.0, 1.0),
    (normalizedRect.bottom - insetY).clamp(0.0, 1.0),
  );

  final left = (cropped.left * image.width).floor().clamp(0, image.width - 1);
  final top = (cropped.top * image.height).floor().clamp(0, image.height - 1);
  final right = (cropped.right * image.width).ceil().clamp(1, image.width);
  final bottom = (cropped.bottom * image.height).ceil().clamp(1, image.height);

  if (right <= left || bottom <= top) return null;

  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;

  final xStep = math.max(1, ((right - left) / 24).floor()).toInt();
  final yStep = math.max(1, ((bottom - top) / 24).floor()).toInt();

  for (var y = top; y < bottom; y += yStep) {
    for (var x = left; x < right; x += xStep) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final maxChannel = [r, g, b].reduce(math.max);
      final minChannel = [r, g, b].reduce(math.min);
      final saturation =
          maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;

      // Prefer vibrant pixels so backgrounds don't wash out the box color.
      if (saturation >= 0.18 || maxChannel >= 220 || minChannel <= 35) {
        red += r;
        green += g;
        blue += b;
        count++;
      }
    }
  }

  if (count == 0) {
    return null;
  }
  return mapRgbToNearestPalette(red ~/ count, green ~/ count, blue ~/ count);
}

// Compute average color of an image file and map to nearest palette color.
Future<ExtractedColor?> extractDominantColor(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final provider = FileImage(file);
    final palette = await PaletteGenerator.fromImageProvider(
      provider,
      size: const Size(200, 200),
      maximumColorCount: 6,
    );

    final dominant = palette.dominantColor?.color;
    if (dominant == null) return null;

    final rAvg = (dominant.r * 255.0).round().clamp(0, 255);
    final gAvg = (dominant.g * 255.0).round().clamp(0, 255);
    final bAvg = (dominant.b * 255.0).round().clamp(0, 255);

    return mapRgbToNearestPalette(rAvg, gAvg, bAvg);
  } catch (e) {
    return null;
  }
}
