/*
Professional Sign → Text realtime screen
- Flutter owns the camera preview and image stream
- Native Android processes each frame through MediaPipe hand landmarker
- Flutter keeps the existing sequence buffer and classifier pipeline
*/

import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'services/native_landmarker_service.dart';

// Constants
const _seqLen = 30;
const _featLen = 63; // 21 landmarks x 3

/// Circular buffer for sequences
class SequenceBuffer {
  final int maxLength;
  final List<List<double>> _buf = [];
  SequenceBuffer({this.maxLength = _seqLen});
  void add(List<double> frame) {
    if (_buf.length >= maxLength) _buf.removeAt(0);
    _buf.add(frame);
  }

  bool get isFull => _buf.length >= maxLength;

  List<double> toFlatArray() {
    if (_buf.isEmpty) return [];
    final out = <double>[];
    final frameLen = _buf[0].length;
    for (final f in _buf){ 
      out.addAll(f);
    }
    final expected = maxLength * frameLen;
    while (out.length < expected){ 
      out.addAll(List.filled(frameLen, 0.0));
    }
    return out;
  }

  void clear() => _buf.clear();
}

/// Dart-side lightweight hand landmark runner (optional)
class HandTrackerLite {
  final Interpreter interpreter;
  final int inputSize;
  HandTrackerLite._(this.interpreter, this.inputSize);

  static Future<HandTrackerLite> create(String assetPath, {int inputSize = 224}) async {
    final opts = InterpreterOptions()..threads = 2;
    // Prefer loading via asset bytes so we can handle any asset path packaging.
    try {
      final key = assetPath.startsWith('assets/') ? assetPath : 'assets/$assetPath';
      final data = await rootBundle.load(key);
      final buf = data.buffer.asUint8List();
      // use fromBuffer if available
      try {
        final interp = Interpreter.fromBuffer(buf, options: opts);
        return HandTrackerLite._(interp, inputSize);
      } catch (e) {
        // fallback to fromAsset attempts
        try {
          final interp2 = await Interpreter.fromAsset(assetPath, options: opts);
          return HandTrackerLite._(interp2, inputSize);
        } catch (_) {
          final alt = assetPath.replaceFirst(RegExp(r'^assets/'), '');
          final interp3 = await Interpreter.fromAsset(alt, options: opts);
          return HandTrackerLite._(interp3, inputSize);
        }
      }
    } catch (e) {
      // final fallback: attempt fromAsset directly
      final opts2 = InterpreterOptions()..threads = 2;
      try {
        final interp = await Interpreter.fromAsset(assetPath, options: opts2);
        return HandTrackerLite._(interp, inputSize);
      } catch (_) {
        final alt = assetPath.replaceFirst(RegExp(r'^assets/'), '');
        final interp2 = await Interpreter.fromAsset(alt, options: opts2);
        return HandTrackerLite._(interp2, inputSize);
      }
    }
  }

  Future<List<double>?> runOnFrame(CameraImage image) async {
    try {
      final rgb = _convertYUV420toRGB(image);
      final resized = _resizeNearest(rgb, image.width, image.height, inputSize, inputSize);

      // Build input [1,h,w,3]
      int idx = 0;
      final shaped = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (y) => List.generate(inputSize, (x) {
            final r = resized[idx++].toDouble() / 255.0;
            final g = resized[idx++].toDouble() / 255.0;
            final b = resized[idx++].toDouble() / 255.0;
            return [r, g, b];
          }),
        ),
      );

      final output = List.filled(1, List.filled(_featLen, 0.0));
      interpreter.run(shaped, output);
      final out0 = output[0] as List;
      final landmarks = out0.map((e) => (e as num).toDouble()).toList();
      return landmarks.length >= _featLen ? landmarks.sublist(0, _featLen) : null;
    } catch (e) {
      debugPrint('HandTrackerLite error: $e');
      return null;
    }
  }

  void close() => interpreter.close();

  static Uint8List _resizeNearest(Uint8List src, int sw, int sh, int dw, int dh) {
    final out = Uint8List(dw * dh * 3);
    for (int y = 0; y < dh; y++) {
      final sy = ((y * sh) / dh).floor().clamp(0, sh - 1);
      for (int x = 0; x < dw; x++) {
        final sx = ((x * sw) / dw).floor().clamp(0, sw - 1);
        final sIdx = (sy * sw + sx) * 3;
        final dIdx = (y * dw + x) * 3;
        out[dIdx] = src[sIdx];
        out[dIdx + 1] = src[sIdx + 1];
        out[dIdx + 2] = src[sIdx + 2];
      }
    }
    return out;
  }

  static Uint8List _convertYUV420toRGB(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final uvRowStride = u.bytesPerRow;
    final uvPixelStride = u.bytesPerPixel ?? 1;

    final out = Uint8List(w * h * 3);
    int oi = 0;
    for (int yy = 0; yy < h; yy++) {
      final uvRow = (yy / 2).floor();
      for (int xx = 0; xx < w; xx++) {
        final uvCol = (xx / 2).floor();
        final yIndex = yy * y.bytesPerRow + xx;
        final uIndex = uvRow * uvRowStride + uvCol * uvPixelStride;
        final vIndex = uvRow * v.bytesPerRow + uvCol * uvPixelStride;
        final Y = y.bytes[yIndex] & 0xff;
        final U = u.bytes[uIndex] & 0xff;
        final V = v.bytes[vIndex] & 0xff;
        int r = (Y + (1.370705 * (V - 128))).round();
        int g = (Y - (0.337633 * (U - 128)) - (0.698001 * (V - 128))).round();
        int b = (Y + (1.732446 * (U - 128))).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        out[oi++] = r;
        out[oi++] = g;
        out[oi++] = b;
      }
    }
    return out;
  }
}

/// Sign classifier wrapper for Dart
class SignClassifier {
  final Interpreter interpreter;
  final List<String> labels;
  SignClassifier._(this.interpreter, this.labels);

  static Future<SignClassifier> create(String modelAsset, String labelsAsset) async {
    final opts = InterpreterOptions()..threads = 2;
    Interpreter interp;
    // Try loading model bytes from bundled assets first and create interpreter from buffer.
    try {
      final candidate = modelAsset.startsWith('assets/') ? modelAsset : 'assets/$modelAsset';
      final data = await rootBundle.load(candidate);
      final buf = data.buffer.asUint8List();
      try {
        interp = Interpreter.fromBuffer(buf, options: opts);
        debugPrint('SignClassifier: loaded model from buffer ($candidate)');
      } catch (e) {
        debugPrint('SignClassifier: fromBuffer failed: $e');
        // fallback to fromAsset
        interp = await Interpreter.fromAsset(modelAsset, options: opts);
      }
    } catch (e) {
      // fallback to trying without assets/ prefix
      try {
        interp = await Interpreter.fromAsset(modelAsset, options: opts);
      } catch (e2) {
        final alt = modelAsset.replaceFirst(RegExp(r'^assets/'), '');
        interp = await Interpreter.fromAsset(alt, options: opts);
      }
    }

    String labTxt;
    try {
      final cand = labelsAsset.startsWith('assets/') ? labelsAsset : 'assets/$labelsAsset';
      labTxt = await rootBundle.loadString(cand);
      debugPrint('SignClassifier: loaded labels from $cand');
    } catch (e) {
      try {
        labTxt = await rootBundle.loadString(labelsAsset);
      } catch (e2) {
        final altLab = labelsAsset.replaceFirst(RegExp(r'^assets/'), '');
        labTxt = await rootBundle.loadString('assets/$altLab');
      }
    }
    final labs = labTxt.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return SignClassifier._(interp, labs);
  }

  /// Run classification on a flattened sequence [seqLen*featLen]
  MapEntry<String, double>? classify(List<double> flat) {
    try {
      final inputShape = interpreter.getInputTensor(0).shape; // e.g. [1,30,63]
      final batch = inputShape[0];
      final seqLen = inputShape.length > 1 ? inputShape[1] : _seqLen;
      final feat = inputShape.length > 2 ? inputShape[2] : _featLen;

      final input = List.generate(batch, (_) => List.generate(seqLen, (i) => List.generate(feat, (j) {
            final idx = i * feat + j;
            return idx < flat.length ? flat[idx] : 0.0;
          })));

      final outShape = interpreter.getOutputTensor(0).shape;
      final nOut = outShape.length > 1 ? outShape[1] : outShape[0];
      final output = List.filled(outShape[0], List.filled(nOut, 0.0));
      interpreter.run(input, output);
      final preds = (output[0] as List).map((e) => (e as num).toDouble()).toList();
      final idx = _argMax(preds);
      final conf = preds[idx];
      final label = idx < labels.length ? labels[idx] : 'CLASS $idx';
      return MapEntry(label, conf);
    } catch (e) {
      debugPrint('SignClassifier classify error: $e');
      return null;
    }
  }

  void close() => interpreter.close();

  int _argMax(List<double> arr) {
    double mv = arr[0];
    int mi = 0;
    for (int i = 1; i < arr.length; i++) if (arr[i] > mv) { mv = arr[i]; mi = i; }
    return mi;
  }
}

/// Overlay painter for landmarks
class LandmarksPainter extends CustomPainter {
  final List<List<double>> hands;
  final bool mirror;
  LandmarksPainter({required this.hands, this.mirror = false});

  static const pairs = <List<int>>[
    [0,1],[1,2],[2,3],[3,4], // thumb
    [0,5],[5,6],[6,7],[7,8], // index
    [0,9],[9,10],[10,11],[11,12], // middle
    [0,13],[13,14],[14,15],[15,16], // ring
    [0,17],[17,18],[18,19],[19,20], // pinky
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;
    final handColors = <Color>[
      Colors.greenAccent,
      Colors.cyanAccent,
    ];

    for (int handIndex = 0; handIndex < hands.length; handIndex++) {
      final landmarks = hands[handIndex];
      if (landmarks.length < _featLen) continue;

      final color = handColors[handIndex % handColors.length];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final dot = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;

      final points = <Offset>[];
      for (int i = 0; i < 21; i++) {
        final x = landmarks[i * 3];
        final y = landmarks[i * 3 + 1];
        final px = mirror ? (1 - x) * size.width : x * size.width;
        final py = y * size.height;
        points.add(Offset(px, py));
      }

      for (final p in pairs) {
        final a = points[p[0]];
        final b = points[p[1]];
        canvas.drawLine(a, b, paint);
      }

      for (final pt in points) {
        canvas.drawCircle(pt, 4.0, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LandmarksPainter old) => old.hands != hands || old.mirror != mirror;
}

/// The polished SignToTextScreen widget
class SignToTextScreen extends StatefulWidget {
  const SignToTextScreen({super.key});
  @override
  State<SignToTextScreen> createState() => _SignToTextScreenState();
}

class _SignToTextScreenState extends State<SignToTextScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _activeCamera;
  bool _isSwitchingCamera = false;
  final NativeLandmarkerService _nativeLandmarker = NativeLandmarkerService();
  bool _nativeReady = false;
  bool _isProcessingFrame = false;

  HandTrackerLite? _handTracker;
  SignClassifier? _signClassifier;
  final SequenceBuffer _sequence = SequenceBuffer();

  List<List<double>> _lastHands = const [];
  String _label = 'Ready';
  double _confidence = 0.0;
  bool _handDetected = false;
  String _detectedSentence = ''; // Accumulated sentence from native camera

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _loadClassifier();
    await _initNativeLandmarker();
    await _initCamera();
  }

  Future<void> _initNativeLandmarker() async {
    try {
      _nativeReady = await _nativeLandmarker.isAvailable();
      debugPrint('Native landmarker available: $_nativeReady');
    } catch (e) {
      _nativeReady = false;
      debugPrint('Native landmarker init failed: $e');
    }
  }

  Future<void> _loadClassifier() async {
    try {
      // _signClassifier = await SignClassifier.create('ml/sign_bridge.tflite', 'ml/labels.json');
      _signClassifier = await SignClassifier.create('models/sign_language_model.tflite', 'models/labels.txt');
      debugPrint('Sign model and labels loaded (${_signClassifier!.labels.length} labels)');

      // Note: Dart hand landmark model not included, using native MediaPipe instead
      _handTracker = null;
      debugPrint('Using native MediaPipe for hand landmarks');
    } catch (e) {
      debugPrint('Failed to load classifier or labels: $e');
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('No cameras available');
        return;
      }
      
      // Prefer front camera for sign language
      final cam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      await _startCamera(cam);
      debugPrint('Camera initialized and image stream started');
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _startCamera(CameraDescription cam) async {
    final previous = _cameraController;
    if (previous != null) {
      if (previous.value.isStreamingImages) {
        await previous.stopImageStream();
      }
      await previous.dispose();
    }

    _isProcessingFrame = false;

    final controller = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

    await controller.initialize();
    await controller.startImageStream(_onCameraImage);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _activeCamera = cam;
      _cameraController = controller;
    });
  }

  Future<void> _switchCamera() async {
    final cameras = _cameras;
    if (cameras == null || cameras.length < 2 || _isSwitchingCamera) {
      return;
    }

    final current = _activeCamera;
    final currentIndex = cameras.indexWhere((c) => c.name == current?.name);
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % cameras.length;
    final nextCamera = cameras[nextIndex];

    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      await _startCamera(nextCamera);
    } catch (e) {
      debugPrint('Camera switch error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_nativeReady || _cameraController == null || _isProcessingFrame || _isSwitchingCamera) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final lm = await _nativeLandmarker.processFrame(
        image,
        rotationDegrees: _rotationDegrees(),
        isFrontCamera: _activeCamera?.lensDirection == CameraLensDirection.front,
      );
      if (lm == null) return;

      if (lm.allHands.isEmpty || lm.primaryLandmarks == null) {
        _handleNoHands();
        return;
      }

      _handleLandmarks(lm.primaryLandmarks!, lm.allHands);
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  int _rotationDegrees() {
    final controller = _cameraController;
    if (controller == null) return 0;

    final deviceDegrees = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final sensorDegrees = controller.description.sensorOrientation;
    if (controller.description.lensDirection == CameraLensDirection.front) {
      return (sensorDegrees + deviceDegrees) % 360;
    }
    return (sensorDegrees - deviceDegrees + 360) % 360;
  }

  void _handleLandmarks(List<double> primary, List<List<double>> hands) {
    if (!mounted) return;

    _lastHands = hands;
    _handDetected = true;
    _sequence.add(primary);
    
    if (_sequence.isFull && _signClassifier != null) {
      try {
        final flat = _sequence.toFlatArray();
        final res = _signClassifier!.classify(flat);
        if (res != null) {
          debugPrint('[CLASSIFICATION] ${res.key}: ${(res.value * 100).toStringAsFixed(1)}%');
          setState(() {
            _label = res.key;
            _confidence = res.value;
          });
        }
        _sequence.clear();
      } catch (e) {
        debugPrint('Classification error: $e');
      }
    } else if (mounted) {
      // Just update landmarks display
      setState(() {});
    }
  }

  void _handleNoHands() {
    if (!mounted) return;

    setState(() {
      _lastHands = const [];
      _handDetected = false;
    });
  }

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
    _cameraController?.dispose();
    _nativeLandmarker.dispose();
    _handTracker?.close();
    _signClassifier?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _cameraController?.value.isInitialized == true
        ? CameraPreview(_cameraController!)
        : const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign → Text — Realtime'),
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            onPressed: (_cameras?.length ?? 0) > 1 && !_isSwitchingCamera ? _switchCamera : null,
            icon: _isSwitchingCamera
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (_lastHands.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LandmarksPainter(
                          hands: _lastHands,
                          mirror: _activeCamera?.lensDirection == CameraLensDirection.front,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_nativeReady ? 'Native MediaPipe stream' : 'Native processor starting', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_handDetected ? '🤚' : '◻️'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _confidence.clamp(0.0, 1.0), minHeight: 10),
                  const SizedBox(height: 8),
                  Text('${(_confidence * 100).toStringAsFixed(1)}%'),
                  const SizedBox(height: 12),
                  if (_detectedSentence.isNotEmpty) ...[
                    const Divider(),
                    const Text('Detected Sentence:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        _detectedSentence,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _detectedSentence = '';
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Sentence'),
                    ),
                  ] else ...[
                    const Text('Camera stream is active in Flutter', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _sequence.clear();
                        _lastHands = const [];
                        _label = 'Ready';
                        _confidence = 0.0;
                        _detectedSentence = '';
                        _handDetected = false;
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
