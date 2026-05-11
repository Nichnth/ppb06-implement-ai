import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_models.dart';

class YoloDetector {
  YoloDetector({
    required this.modelAssetPath,
    this.modelBytes,
    this.inputSize = 320,
    this.scoreThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.enableGpuDelegate = false,
    this.enableNnApiDelegate = true,
  });

  final String modelAssetPath;
  final Uint8List? modelBytes;
  final int inputSize;
  final double scoreThreshold;
  final double iouThreshold;
  final bool enableGpuDelegate;
  final bool enableNnApiDelegate;

  Interpreter? _interpreter;

  bool get isReady => _interpreter != null;

  Future<void> load() async {
    if (_interpreter != null) return;

    final options = InterpreterOptions();
    if (!kIsWeb) {
      options.threads = 2;
      if (enableGpuDelegate) {
        try {
          options.addDelegate(GpuDelegateV2());
        } catch (_) {
          if (enableNnApiDelegate && defaultTargetPlatform == TargetPlatform.android) {
            options.useNnApiForAndroid = true;
          }
        }
      } else if (enableNnApiDelegate && defaultTargetPlatform == TargetPlatform.android) {
        options.useNnApiForAndroid = true;
      }
    }

    if (modelBytes != null) {
      _interpreter = Interpreter.fromBuffer(modelBytes!, options: options);
    } else {
      _interpreter = await Interpreter.fromAsset(modelAssetPath, options: options);
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }

  Future<List<DetectionBox>> detect(img.Image sourceImage) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('YoloDetector is not loaded.');
    }

    final input = _preprocess(sourceImage);
    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final output = _createZeroBuffer(outputShape);

    interpreter.run(input, output);

    final detections = _decodeOutput(output, outputShape);
    return _nonMaximumSuppression(detections);
  }

  List<List<List<List<double>>>> _preprocess(img.Image image) {
    final resized = image.width == inputSize && image.height == inputSize
        ? image
        : img.copyResize(image, width: inputSize, height: inputSize);
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (_) => List.generate(inputSize, (_) => List<double>.filled(3, 0)),
      ),
    );

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0;
        input[0][y][x][1] = pixel.g / 255.0;
        input[0][y][x][2] = pixel.b / 255.0;
      }
    }

    return input;
  }

  dynamic _createZeroBuffer(List<int> shape) {
    if (shape.length == 2) {
      return List.generate(shape[0], (_) => List<double>.filled(shape[1], 0));
    }
    if (shape.length == 3) {
      return List.generate(
        shape[0],
        (_) => List.generate(shape[1], (_) => List<double>.filled(shape[2], 0)),
      );
    }

    throw UnsupportedError('Unsupported output shape: $shape');
  }

  List<DetectionBox> _decodeOutput(dynamic output, List<int> shape) {
    if (shape.length == 2) {
      final rows = (output[0] as List).cast<double>();
      return _decodeFlatRow(rows);
    }

    final List<dynamic> batch = (output as List).first as List<dynamic>;
    if (batch.isEmpty || batch.first is! List) {
      return const [];
    }

    final firstSub = batch.first as List;
    final channelsFirst = batch.length < firstSub.length;

    return channelsFirst
        ? _decodeChannelsFirst(batch.cast<List<dynamic>>())
        : _decodeChannelsLast(batch.cast<List<dynamic>>());
  }

  List<DetectionBox> _decodeFlatRow(List<double> row) {
    if (row.length < 6) return const [];

    final xCenter = row[0];
    final yCenter = row[1];
    final width = row[2];
    final height = row[3];
    final objectness = row[4];

    var classId = 0;
    var classScore = 1.0;
    if (row.length > 5) {
      classScore = 0;
      for (var i = 5; i < row.length; i++) {
        if (row[i] > classScore) {
          classScore = row[i];
          classId = i - 5;
        }
      }
    }

    final confidence = objectness * classScore;
    if (confidence < scoreThreshold) return const [];

    return [
      _buildDetection(
        xCenter: xCenter,
        yCenter: yCenter,
        width: width,
        height: height,
        confidence: confidence,
        classId: classId,
      ),
    ];
  }

  List<DetectionBox> _decodeChannelsFirst(List<List<dynamic>> channels) {
    if (channels.length < 5) return const [];

    final candidates = channels[0].length;
    final features = channels.length;
    final hasObjectness = features >= 85;
    final detections = <DetectionBox>[];

    for (var i = 0; i < candidates; i++) {
      final xCenter = (channels[0][i] as num).toDouble();
      final yCenter = (channels[1][i] as num).toDouble();
      final width = (channels[2][i] as num).toDouble();
      final height = (channels[3][i] as num).toDouble();

      var classStart = 4;
      var objectness = 1.0;
      if (hasObjectness) {
        objectness = (channels[4][i] as num).toDouble();
        classStart = 5;
      }

      var classScore = 0.0;
      var classId = 0;
      for (var c = classStart; c < features; c++) {
        final score = (channels[c][i] as num).toDouble();
        if (score > classScore) {
          classScore = score;
          classId = c - classStart;
        }
      }

      final confidence = objectness * classScore;
      if (confidence < scoreThreshold) continue;

      detections.add(
        _buildDetection(
          xCenter: xCenter,
          yCenter: yCenter,
          width: width,
          height: height,
          confidence: confidence,
          classId: classId,
        ),
      );
    }

    return detections;
  }

  List<DetectionBox> _decodeChannelsLast(List<List<dynamic>> rows) {
    final detections = <DetectionBox>[];
    if (rows.isEmpty) return detections;

    final features = rows.first.length;
    final hasObjectness = features >= 85;

    for (final row in rows) {
      if (row.length < 6) continue;

      final xCenter = (row[0] as num).toDouble();
      final yCenter = (row[1] as num).toDouble();
      final width = (row[2] as num).toDouble();
      final height = (row[3] as num).toDouble();

      var classStart = 4;
      var objectness = 1.0;
      if (hasObjectness) {
        objectness = (row[4] as num).toDouble();
        classStart = 5;
      }

      var classScore = 0.0;
      var classId = 0;
      for (var c = classStart; c < features; c++) {
        final score = (row[c] as num).toDouble();
        if (score > classScore) {
          classScore = score;
          classId = c - classStart;
        }
      }

      final confidence = objectness * classScore;
      if (confidence < scoreThreshold) continue;

      detections.add(
        _buildDetection(
          xCenter: xCenter,
          yCenter: yCenter,
          width: width,
          height: height,
          confidence: confidence,
          classId: classId,
        ),
      );
    }

    return detections;
  }

  DetectionBox _buildDetection({
    required double xCenter,
    required double yCenter,
    required double width,
    required double height,
    required double confidence,
    required int classId,
  }) {
    final scaledX = xCenter > 1.0 ? xCenter / inputSize : xCenter;
    final scaledY = yCenter > 1.0 ? yCenter / inputSize : yCenter;
    final scaledW = width > 1.0 ? width / inputSize : width;
    final scaledH = height > 1.0 ? height / inputSize : height;

    final left = (scaledX - scaledW / 2).clamp(0.0, 1.0);
    final top = (scaledY - scaledH / 2).clamp(0.0, 1.0);
    final right = (scaledX + scaledW / 2).clamp(0.0, 1.0);
    final bottom = (scaledY + scaledH / 2).clamp(0.0, 1.0);

    return DetectionBox(
      rect: Rect.fromLTRB(left, top, right, bottom),
      score: confidence,
      classId: classId,
      label: 'Object $classId',
    );
  }

  List<DetectionBox> _nonMaximumSuppression(List<DetectionBox> detections) {
    if (detections.isEmpty) return detections;

    final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
    final selected = <DetectionBox>[];

    while (sorted.isNotEmpty) {
      final current = sorted.removeAt(0);
      selected.add(current);

      sorted.removeWhere(
          (other) => _iou(current.rect, other.rect) > iouThreshold);
    }

    return selected;
  }

  double _iou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);

    final intersectionWidth = math.max(0.0, right - left);
    final intersectionHeight = math.max(0.0, bottom - top);
    final intersection = intersectionWidth * intersectionHeight;

    final union = a.width * a.height + b.width * b.height - intersection;
    if (union <= 0) return 0;

    return intersection / union;
  }
}
