/*
Sign → Text realtime screen
- Flutter owns the camera preview and image stream.
- Native Android runs MediaPipe Holistic and returns the 180-landmark feature
  vector the Sign Bridge GRU model was trained on.
- Frames are buffered per "sign": while a hand is visible we collect frames;
  when the hand disappears we run the model on the collected clip, show the
  top-3 words, and append the best one to the sentence.
*/

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/native_landmarker_service.dart';
import 'services/sign_bridge_inference.dart';
import 'models/prediction.dart';

// Segmentation tuning.
const _minFramesForSign = 12; // ignore clips shorter than this
const _maxFramesBuffer = 96; // cap buffer length (~a few seconds)
const _framesAbsentToPredict = 6; // hand gone this many frames => sign ended
const _appendThreshold = 0.25; // min cosine sim to append a word to the sentence

/// Overlay painter for hand landmarks (21 points each).
class LandmarksPainter extends CustomPainter {
  final List<List<double>> hands;
  final bool mirror;
  LandmarksPainter({required this.hands, this.mirror = false});

  static const pairs = <List<int>>[
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [0, 9], [9, 10], [10, 11], [11, 12], // middle
    [0, 13], [13, 14], [14, 15], [15, 16], // ring
    [0, 17], [17, 18], [18, 19], [19, 20], // pinky
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;
    final handColors = <Color>[Colors.greenAccent, Colors.cyanAccent];

    for (int handIndex = 0; handIndex < hands.length; handIndex++) {
      final landmarks = hands[handIndex];
      if (landmarks.length < 63) continue;

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
        canvas.drawLine(points[p[0]], points[p[1]], paint);
      }
      for (final pt in points) {
        canvas.drawCircle(pt, 4.0, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LandmarksPainter old) =>
      old.hands != hands || old.mirror != mirror;
}

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

  SignBridgeInference? _model;
  String _modelStatus = 'Loading model...';

  // Per-sign frame buffer. Each entry is a flat 540-length (180x3) vector.
  final List<List<double>> _frameBuffer = [];
  int _framesAbsent = 0;
  bool _isPredicting = false;

  List<List<double>> _lastHands = const [];
  bool _handDetected = false;

  String _label = 'Ready';
  double _confidence = 0.0;
  List<Prediction> _topPreds = const [];
  String _sentence = '';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _loadModel();
    await _initNativeLandmarker();
    await _initCamera();
  }

  Future<void> _loadModel() async {
    try {
      _model = await SignBridgeInference.create();
      if (!mounted) return;
      setState(() => _modelStatus = 'Model ready (${_model!.names.length} words)');
    } catch (e) {
      debugPrint('Failed to load Sign Bridge model: $e');
      if (!mounted) return;
      setState(() => _modelStatus = 'Model failed to load: $e');
    }
  }

  Future<void> _initNativeLandmarker() async {
    try {
      _nativeReady = await _nativeLandmarker.isAvailable();
      debugPrint('Native holistic landmarker available: $_nativeReady');
    } catch (e) {
      _nativeReady = false;
      debugPrint('Native landmarker init failed: $e');
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('No cameras available');
        return;
      }
      final cam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      await _startCamera(cam);
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
    if (cameras == null || cameras.length < 2 || _isSwitchingCamera) return;

    final current = _activeCamera;
    final currentIndex = cameras.indexWhere((c) => c.name == current?.name);
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % cameras.length;

    setState(() => _isSwitchingCamera = true);
    try {
      _resetBuffer();
      await _startCamera(cameras[nextIndex]);
    } catch (e) {
      debugPrint('Camera switch error: $e');
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_nativeReady ||
        _cameraController == null ||
        _isProcessingFrame ||
        _isSwitchingCamera ||
        _isPredicting) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final frame = await _nativeLandmarker.processFrame(
        image,
        rotationDegrees: _rotationDegrees(),
        isFrontCamera: _activeCamera?.lensDirection == CameraLensDirection.front,
      );
      if (frame == null) return;
      _handleFrame(frame);
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

  void _handleFrame(NativeFrameResult frame) {
    if (!mounted) return;

    if (frame.hasHands && frame.landmarks180 != null) {
      // Collect this frame into the current sign clip.
      _framesAbsent = 0;
      if (_frameBuffer.length >= _maxFramesBuffer) _frameBuffer.removeAt(0);
      _frameBuffer.add(frame.landmarks180!);
      setState(() {
        _lastHands = frame.overlayHands;
        _handDetected = true;
      });
    } else {
      // No hands this frame — maybe the sign just ended.
      _framesAbsent++;
      if (_handDetected) {
        setState(() {
          _lastHands = const [];
          _handDetected = false;
        });
      }
      if (_frameBuffer.length >= _minFramesForSign &&
          _framesAbsent >= _framesAbsentToPredict) {
        _runPrediction();
      }
    }
  }

  Future<void> _runPrediction() async {
    final model = _model;
    if (model == null || _isPredicting || _frameBuffer.isEmpty) return;

    _isPredicting = true;
    // Snapshot + clear so new signing can start immediately.
    final clip = List<List<double>>.from(_frameBuffer);
    _frameBuffer.clear();
    _framesAbsent = 0;

    try {
      // Reshape each flat 540 frame into [180][3].
      final landmarks = clip
          .map((flat) => List.generate(
                180,
                (l) => [flat[l * 3], flat[l * 3 + 1], flat[l * 3 + 2]],
              ))
          .toList();

      final preds = model.predict(landmarks);
      if (!mounted) return;
      setState(() {
        _topPreds = preds;
        if (preds.isNotEmpty) {
          _label = preds.first.word;
          _confidence = preds.first.confidence;
          if (preds.first.confidence >= _appendThreshold) {
            _appendWord(preds.first.word);
          }
        }
      });
    } catch (e) {
      debugPrint('Prediction error: $e');
      if (mounted) setState(() => _label = 'Inference error');
    } finally {
      _isPredicting = false;
    }
  }

  void _appendWord(String word) {
    // Avoid repeating the same word twice in a row.
    final trimmed = _sentence.trimRight();
    if (trimmed.endsWith(word)) return;
    _sentence = _sentence.isEmpty ? word : '$_sentence $word';
  }

  void _resetBuffer() {
    _frameBuffer.clear();
    _framesAbsent = 0;
  }

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
    _cameraController?.dispose();
    _nativeLandmarker.dispose();
    _model?.dispose();
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
            onPressed: (_cameras?.length ?? 0) > 1 && !_isSwitchingCamera
                ? _switchCamera
                : null,
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
                          mirror: _activeCamera?.lensDirection ==
                              CameraLensDirection.front,
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
                      Flexible(
                        child: Text(
                          _nativeReady ? _modelStatus : 'Starting native processor…',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_handDetected
                          ? '🤚 ${_frameBuffer.length}'
                          : (_isPredicting ? '⏳' : '◻️')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_label,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value: _confidence.clamp(0.0, 1.0), minHeight: 10),
                  const SizedBox(height: 4),
                  Text('${(_confidence * 100).toStringAsFixed(1)}% match'),
                  if (_topPreds.length > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      'also: ${_topPreds.skip(1).map((p) => '${p.word} (${(p.confidence * 100).toStringAsFixed(0)}%)').join(', ')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sentence:',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      _sentence.isEmpty ? 'Sign a word…' : _sentence,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _resetBuffer();
                        _lastHands = const [];
                        _label = 'Ready';
                        _confidence = 0.0;
                        _topPreds = const [];
                        _sentence = '';
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
