import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'detection_models.dart';
import 'yolo_detector.dart';

class InferenceWorker {
  InferenceWorker({
    required this.modelBytes,
    this.inputSize = 320,
    this.scoreThreshold = 0.35,
    this.iouThreshold = 0.45,
  });

  final Uint8List modelBytes;
  final int inputSize;
  final double scoreThreshold;
  final double iouThreshold;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _commandPort;
  final Map<int, Completer<List<DetectionBox>>> _pending = {};
  int _nextRequestId = 0;
  final Completer<void> _ready = Completer<void>();

  Future<void> start() async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage, onError: (error) {
      if (!_ready.isCompleted) {
        _ready.completeError(error);
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      {
        'replyTo': _receivePort!.sendPort,
        'modelBytes': TransferableTypedData.fromList([modelBytes]),
        'inputSize': inputSize,
        'scoreThreshold': scoreThreshold,
        'iouThreshold': iouThreshold,
      },
      debugName: 'yolo-inference-worker',
    );

    await _ready.future;
  }

  Future<List<DetectionBox>> infer(img.Image image) async {
    final commandPort = _commandPort;
    if (commandPort == null) {
      throw StateError('Inference worker has not started.');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<List<DetectionBox>>();
    _pending[requestId] = completer;

    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    commandPort.send({
      'type': 'infer',
      'id': requestId,
      'width': image.width,
      'height': image.height,
      'frame': TransferableTypedData.fromList([bytes]),
    });

    return completer.future;
  }

  Future<void> dispose() async {
    _commandPort?.send({'type': 'close'});
    _pending.forEach((_, completer) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Inference worker closed.'));
      }
    });
    _pending.clear();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _commandPort = message;
      if (!_ready.isCompleted) {
        _ready.complete();
      }
      return;
    }

    if (message is Map) {
      final id = message['id'] as int?;
      if (id == null) return;

      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;

      final detectionsJson = (message['detections'] as List<dynamic>? ?? const []);
      final detections = detectionsJson
          .map((entry) => DetectionBox.fromJson(Map<String, dynamic>.from(entry as Map)))
          .toList(growable: false);
      completer.complete(detections);
      return;
    }
  }
}


Future<void> _workerMain(Map<String, dynamic> init) async {
  final replyTo = init['replyTo'] as SendPort;
  final modelBytes = (init['modelBytes'] as TransferableTypedData)
      .materialize()
      .asUint8List();
  final inputSize = init['inputSize'] as int;
  final scoreThreshold = init['scoreThreshold'] as double;
  final iouThreshold = init['iouThreshold'] as double;

  final detector = YoloDetector(
    modelAssetPath: 'assets/models/yolov5n.tflite',
    modelBytes: modelBytes,
    inputSize: inputSize,
    scoreThreshold: scoreThreshold,
    iouThreshold: iouThreshold,
    enableGpuDelegate: true,
    enableNnApiDelegate: true,
  );
  await detector.load();

  final port = ReceivePort();
  replyTo.send(port.sendPort);

  await for (final message in port) {
    if (message is Map && message['type'] == 'infer') {
      final id = message['id'] as int;
      final width = message['width'] as int;
      final height = message['height'] as int;
      final frameBytes = (message['frame'] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final frame = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: frameBytes.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );
      final detections = await detector.detect(frame);
      replyTo.send({
        'id': id,
        'detections': detections.map((d) => d.toJson()).toList(),
      });
      continue;
    }

    if (message is Map && message['type'] == 'close') {
      detector.close();
      port.close();
      break;
    }
  }
}

