import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../detection/camera_image_converter.dart';
import '../detection/color_extractor.dart';
import '../detection/detection_models.dart';
import '../detection/inference_worker.dart';

class LiveCameraPage extends StatefulWidget {
  const LiveCameraPage({
    super.key,
    required this.onColorDetected,
  });

  final Future<void> Function(String colorName, String hex, String filePath)
      onColorDetected;

  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage> {
  static const _modelAssetPath = 'assets/models/yolov5n.tflite';
  static const _modelInputSize = 320;
  static const _inferenceIntervalMs = 400;

  CameraController? _controller;
  InferenceWorker? _worker;

  bool _isInitializing = true;
  bool _isProcessingFrame = false;
  bool _isCapturing = false;
  bool _isModelReady = false;

  String? _statusMessage;
  DateTime _lastInferenceAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<DetectionBox> _detections = const [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _statusMessage = 'No camera available on this device.';
          _isInitializing = false;
        });
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      try {
        final modelData = await rootBundle.load(_modelAssetPath);
        final worker = InferenceWorker(
          modelBytes: modelData.buffer.asUint8List(),
          inputSize: _modelInputSize,
          scoreThreshold: 0.35,
          iouThreshold: 0.45,
        );
        await worker.start();
        _worker = worker;
        _isModelReady = true;
      } catch (_) {
        _statusMessage =
            'Model not found at $_modelAssetPath. Add the .tflite file and restart.';
      }

      if (_isModelReady) {
        await controller.startImageStream(_onCameraImage);
      }

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to initialize camera: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_isModelReady || _isProcessingFrame || _isCapturing) return;

    final now = DateTime.now();
    if (now.difference(_lastInferenceAt).inMilliseconds <
        _inferenceIntervalMs) {
      return;
    }

    _isProcessingFrame = true;
    _lastInferenceAt = now;

    try {
      final rgbImage = cameraImageToRgb(
        image,
        targetWidth: _modelInputSize,
        targetHeight: _modelInputSize,
      );
      final rawDetections = await _worker!.infer(rgbImage);
      final labeled = rawDetections.map((detection) {
        final colorTags = extractColorTagsFromRegion(rgbImage, detection.rect);
        if (colorTags.isEmpty) return detection;
        return detection.copyWith(
          colorName: colorTags.first.name,
          colorHex: colorTags.first.hex,
          colorTags: colorTags.map((tag) => tag.name).toList(growable: false),
        );
      }).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _detections = labeled;
      });
    } catch (_) {
      // Keep the stream alive even if one frame fails.
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _captureAndSave() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final picture = await controller.takePicture();
      final originalBytes = await File(picture.path).readAsBytes();
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        throw Exception('Failed to decode captured image.');
      }

      final annotated = _drawDetectionsOnImage(decoded, _detections);
      final outputPath = await _writeAnnotatedImage(annotated);

      final fileName = 'colorcam_${DateTime.now().millisecondsSinceEpoch}';
      final saveResult = await SaverGallery.saveFile(
        filePath: outputPath,
        fileName: fileName,
        skipIfExists: false,
      );

      if (!mounted) return;

      if (saveResult.isSuccess) {
        await _persistColors(outputPath);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saveResult.isSuccess
                ? 'Annotated photo saved to gallery.'
                : 'Photo captured, but gallery save failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<String> _writeAnnotatedImage(img.Image image) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path =
        '${docsDir.path}${Platform.pathSeparator}colorcam_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(path);
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));
    return file.path;
  }

  Future<void> _persistColors(String imagePath) async {
    final unique = <String, String>{};

    for (final detection in _detections) {
      final tags = detection.colorTags.isNotEmpty
          ? detection.colorTags
          : [if (detection.colorName != null) detection.colorName!];
      for (final tag in tags) {
        unique[tag] = mapColorNameToHex(tag);
      }
    }

    if (unique.isEmpty) {
      final fallback = await extractDominantColor(imagePath);
      if (fallback != null) {
        await widget.onColorDetected(
          fallback.name,
          fallback.hex,
          imagePath,
        );
      }
      return;
    }

    for (final entry in unique.entries) {
      await widget.onColorDetected(entry.key, entry.value, imagePath);
    }
  }

  img.Image _drawDetectionsOnImage(
      img.Image source, List<DetectionBox> detections) {
    final output =
        img.copyResize(source, width: source.width, height: source.height);

    for (final detection in detections) {
      final left = (detection.rect.left * output.width)
          .round()
          .clamp(0, output.width - 1);
      final top = (detection.rect.top * output.height)
          .round()
          .clamp(0, output.height - 1);
      final right =
          (detection.rect.right * output.width).round().clamp(1, output.width);
      final bottom = (detection.rect.bottom * output.height)
          .round()
          .clamp(1, output.height);
      if (right <= left || bottom <= top) continue;

      final color = _hexToImageColor(detection.colorHex ?? '#00FF00');

      img.drawRect(
        output,
        x1: left,
        y1: top,
        x2: right,
        y2: bottom,
        color: color,
        thickness: 3,
      );

      final labelText = detection.colorTags.isNotEmpty
          ? detection.colorTags.join(' • ')
          : detection.colorName ?? detection.label ?? 'Object';
      final label = '$labelText ${(detection.score * 100).toStringAsFixed(0)}%';
      final labelWidth = label.length * 9;
      final labelHeight = 20;
      final labelTop =
          (top - labelHeight).clamp(0, output.height - labelHeight);
      final labelRight = (left + labelWidth).clamp(0, output.width);

      img.fillRect(
        output,
        x1: left,
        y1: labelTop,
        x2: labelRight,
        y2: labelTop + labelHeight,
        color: color,
      );

      img.drawString(
        output,
        label,
        font: img.arial14,
        x: left + 3,
        y: labelTop + 3,
        color: img.ColorRgb8(0, 0, 0),
      );
    }

    return output;
  }

  img.Color _hexToImageColor(String hex) {
    final cleaned = hex.replaceAll('#', '').padLeft(6, '0');
    final value = int.parse(cleaned, radix: 16);
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    return img.ColorRgb8(r, g, b);
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
    controller?.dispose();
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Color Detection')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : controller == null
              ? Center(child: Text(_statusMessage ?? 'Unable to open camera.'))
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: CameraPreview(controller),
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _DetectionOverlayPainter(
                                  detections: _detections),
                            ),
                          ),
                          if (_statusMessage != null)
                            Positioned(
                              top: 12,
                              left: 12,
                              right: 12,
                              child: Card(
                                color: Colors.black87,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _statusMessage!,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isCapturing ? null : _captureAndSave,
                          icon: _isCapturing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(_isCapturing
                              ? 'Saving...'
                              : 'Capture with overlay'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _DetectionOverlayPainter extends CustomPainter {
  _DetectionOverlayPainter({required this.detections});

  final List<DetectionBox> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final color = _parseColor(detection.colorHex ?? '#00FF00');
      final rect = Rect.fromLTRB(
        detection.rect.left * size.width,
        detection.rect.top * size.height,
        detection.rect.right * size.width,
        detection.rect.bottom * size.height,
      );

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color;
      canvas.drawRect(rect, border);

      final label =
          '${detection.colorName ?? detection.label ?? 'Object'} ${(detection.score * 100).toStringAsFixed(0)}%';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.8);

      final labelRect = Rect.fromLTWH(
        rect.left,
        (rect.top - painter.height - 6)
            .clamp(0, size.height - painter.height - 2),
        painter.width + 8,
        painter.height + 4,
      );

      final bg = Paint()..color = color;
      canvas.drawRect(labelRect, bg);
      painter.paint(canvas, Offset(labelRect.left + 4, labelRect.top + 2));
    }
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
