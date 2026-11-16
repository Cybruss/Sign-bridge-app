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
import 'screens/asl_dictionary_screen.dart';
import 'services/fingerspelling_inference.dart';

// Segmentation tuning.
const _minFramesForSign = 12; // ignore clips shorter than this
const _maxFramesBuffer = 96; // cap buffer length (~a few seconds)
const _framesAbsentToPredict = 6; // hand gone this many frames => sign ended
const _overlayMissGraceFrames =
    3; // keep the skeleton stable through brief detector misses
const _minimumLetterScore = 0.93;
const _minimumLetterMargin = 0.18;

enum _RecognitionMode { words, fingerspelling }

/// Overlay painter for the same 180 selected points the word model consumes.
class LandmarksPainter extends CustomPainter {
  final List<double> landmarks;
  final bool mirror;
  final bool showUpperBodyAndFace;
  LandmarksPainter({
    required this.landmarks,
    this.mirror = false,
    this.showUpperBodyAndFace = true,
  });

  static const pairs = <List<int>>[
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [0, 9], [9, 10], [10, 11], [11, 12], // middle
    [0, 13], [13, 14], [14, 15], [15, 16], // ring
    [0, 17], [17, 18], [18, 19], [19, 20], // pinky
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.length < 180 * 3) return;
    Offset point(int index) {
      final x = landmarks[index * 3];
      final y = landmarks[index * 3 + 1];
      final z = landmarks[index * 3 + 2];
      if (!x.isFinite ||
          !y.isFinite ||
          !z.isFinite ||
          (x == 0 && y == 0 && z == 0)) {
        return const Offset(double.nan, double.nan);
      }
      return Offset((mirror ? 1 - x : x) * size.width, y * size.height);
    }

    bool visible(Offset p) =>
        p.dx.isFinite &&
        p.dy.isFinite &&
        p.dx >= 0 &&
        p.dx <= size.width &&
        p.dy >= 0 &&
        p.dy <= size.height;

    void drawHand(int start, Color color) {
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = color.withValues(alpha: .9);
      for (final pair in pairs) {
        final a = point(start + pair[0]);
        final b = point(start + pair[1]);
        if (visible(a) && visible(b)) canvas.drawLine(a, b, stroke);
      }
      for (var i = 0; i < 21; i++) {
        final p = point(start + i);
        if (visible(p)) canvas.drawCircle(p, 3.2, dot);
      }
    }

    drawHand(0, Colors.greenAccent);
    drawHand(21, Colors.cyanAccent);

    if (!showUpperBodyAndFace) return;

    // Selected pose points are shoulders, elbows and wrists.
    final poseStroke = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.5;
    for (final pair in const [
      [42, 44],
      [44, 46],
      [43, 45],
      [45, 47],
      [42, 43],
    ]) {
      final a = point(pair[0]);
      final b = point(pair[1]);
      if (visible(a) && visible(b)) canvas.drawLine(a, b, poseStroke);
    }
    final poseDot = Paint()..color = Colors.amberAccent;
    for (var i = 42; i < 48; i++) {
      final p = point(i);
      if (visible(p)) canvas.drawCircle(p, 4.5, poseDot);
    }

    // The face input is a sparse selected subset, so display points without
    // suggesting that this is a complete face mesh.
    final faceDot = Paint()..color = Colors.pinkAccent;
    for (var i = 48; i < 180; i++) {
      final p = point(i);
      if (visible(p)) canvas.drawCircle(p, 2.1, faceDot);
    }
  }

  @override
  bool shouldRepaint(covariant LandmarksPainter old) =>
      old.landmarks != landmarks ||
      old.mirror != mirror ||
      old.showUpperBodyAndFace != showUpperBodyAndFace;
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
  bool _cameraRunning = false;
  String _cameraStatus = 'Starting camera…';

  final NativeLandmarkerService _nativeLandmarker = NativeLandmarkerService();
  bool _nativeReady = false;
  String _landmarkerStatus = 'Starting Holistic processor…';
  bool _isProcessingFrame = false;

  SignBridgeInference? _model;
  String _modelStatus = 'Loading model...';
  FingerspellingInference? _fingerspellingModel;
  String _fingerspellingStatus = 'Loading static alphabet fallback…';
  _RecognitionMode _recognitionMode = _RecognitionMode.words;
  final List<String> _letterVotes = [];
  int _letterFrameCounter = 0;
  String _letterCandidate = '—';
  bool _letterIsConfident = false;
  String? _latchedLetter;
  int _framesWithoutHands = 0;

  // Per-sign frame buffer. Each entry is a flat 540-length (180x3) vector.
  final List<List<double>> _frameBuffer = [];
  int _framesAbsent = 0;
  int _overlayMisses = 0;
  bool _isPredicting = false;

  List<List<double>> _lastHands = const [];
  List<double>? _lastModelLandmarks;
  bool _handDetected = false;

  String _label = 'Show one sign to begin';
  List<Prediction> _topPreds = const [];
  String _sentence = '';
  final TextEditingController _sentenceController = TextEditingController();

  String get _userStatus {
    final camera = _cameraStatus.toLowerCase();
    if (camera.contains('permission')) return 'Allow camera access in Settings';
    if (camera.contains('no camera')) return 'No camera is available';
    if (camera.contains('unavailable') || camera.contains('could not')) {
      return 'The camera could not start';
    }
    final landmarker = _landmarkerStatus.toLowerCase();
    if (landmarker.contains('unavailable') || landmarker.contains('failed')) {
      return 'Sign recognition is unavailable on this device';
    }
    if (_recognitionMode == _RecognitionMode.words &&
        _modelStatus.toLowerCase().contains('failed')) {
      return 'Sign recognition could not start';
    }
    if (_recognitionMode == _RecognitionMode.fingerspelling &&
        _fingerspellingStatus.toLowerCase().contains('unavailable')) {
      return 'Letter spelling could not start';
    }
    if (!_nativeReady ||
        (_recognitionMode == _RecognitionMode.words && _model == null) ||
        (_recognitionMode == _RecognitionMode.fingerspelling &&
            _fingerspellingModel == null)) {
      return 'Preparing sign recognition…';
    }
    if (!_cameraRunning) return 'Camera paused';
    if (!_handDetected) return 'Camera ready · show your signing hand';
    if (_recognitionMode == _RecognitionMode.fingerspelling) {
      if (_fingerspellingStatus.startsWith('Low match')) {
        return 'Hand in view · adjust your hand shape';
      }
      if (_fingerspellingStatus.startsWith('Added')) {
        return 'Letter added · lower your hand for the next one';
      }
      return 'Hand in view · hold the shape steady';
    }
    return 'Hand in view · sign one word';
  }

  String get _userPredictionLabel {
    if (_label == 'Ready' || _label == 'Show one sign to begin') {
      return 'Show one sign to begin';
    }
    if (_label == 'Inference error') return 'Could not recognize that sign';
    return _label;
  }

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await Future.wait([
      _loadModel(),
      _loadFingerspellingModel(),
      _initNativeLandmarker(),
    ]);
    await _initCamera();
  }

  Future<void> _loadModel() async {
    try {
      _model = await SignBridgeInference.create();
      if (!mounted) return;
      setState(
        () => _modelStatus = 'Model ready (${_model!.names.length} words)',
      );
    } catch (e) {
      debugPrint('Failed to load Sign Bridge model: $e');
      if (!mounted) return;
      setState(() => _modelStatus = 'Model failed to load: $e');
    }
  }

  Future<void> _loadFingerspellingModel() async {
    try {
      _fingerspellingModel = await FingerspellingInference.create();
      if (!mounted) return;
      setState(
        () => _fingerspellingStatus =
            'Static alphabet model ready (${_fingerspellingModel!.names.length} letters)',
      );
    } catch (error) {
      debugPrint('Failed to load fingerspelling model: $error');
      if (!mounted) return;
      setState(
        () => _fingerspellingStatus = 'Alphabet fallback unavailable: $error',
      );
    }
  }

  Future<void> _initNativeLandmarker() async {
    try {
      _nativeReady = await _nativeLandmarker.isAvailable();
      _landmarkerStatus = _nativeReady
          ? 'Holistic processor ready'
          : 'Holistic processor unavailable; recognition is disabled';
      debugPrint('Native holistic landmarker available: $_nativeReady');
      if (mounted) setState(() {});
    } catch (e) {
      _nativeReady = false;
      _landmarkerStatus = 'Holistic processor failed to initialize';
      debugPrint('Native landmarker init failed: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('No cameras available');
        if (mounted) {
          setState(
            () => _cameraStatus = 'No camera is available on this device.',
          );
        }
        return;
      }
      final cam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      await _startCamera(cam);
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (!mounted) return;
      final denied = e.toString().toLowerCase().contains('denied');
      setState(
        () => _cameraStatus = denied
            ? 'Camera permission was denied. Enable camera access in system settings.'
            : 'Camera unavailable. Check camera permission and device status.',
      );
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
      // Medium gives Holistic more hand pixels, reducing missed detections;
      // the native processor still drops frames while inference is busy.
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
      _cameraRunning = true;
      _cameraStatus = 'Camera running';
    });
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    if (controller == null || !_cameraRunning) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _resetBuffer();
      if (mounted) {
        setState(() {
          _cameraRunning = false;
          _cameraStatus = 'Camera paused';
          _lastHands = const [];
          _handDetected = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cameraStatus = 'Could not stop camera: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraRunning) {
      await _stopCamera();
      return;
    }
    final controller = _cameraController;
    if (controller?.value.isInitialized == true) {
      try {
        await controller!.startImageStream(_onCameraImage);
        if (mounted) {
          setState(() {
            _cameraRunning = true;
            _cameraStatus = 'Camera running';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _cameraStatus = 'Could not start camera: $e');
        }
      }
      return;
    }
    await _initCamera();
  }

  Future<void> _switchCamera() async {
    final cameras = _cameras;
    if (cameras == null || cameras.length < 2 || _isSwitchingCamera) return;

    final current = _activeCamera;
    final currentIndex = cameras.indexWhere((c) => c.name == current?.name);
    final nextIndex = currentIndex == -1
        ? 0
        : (currentIndex + 1) % cameras.length;

    setState(() => _isSwitchingCamera = true);
    try {
      _resetBuffer();
      await _startCamera(cameras[nextIndex]);
    } catch (e) {
      debugPrint('Camera switch error: $e');
      if (mounted) {
        setState(
          () => _cameraStatus =
              'Camera switch failed. Try restarting the camera.',
        );
      }
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
        isFrontCamera:
            _activeCamera?.lensDirection == CameraLensDirection.front,
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

    if (_recognitionMode == _RecognitionMode.fingerspelling) {
      _handleFingerspellingFrame(frame);
      return;
    }

    if (frame.hasHands && frame.landmarks180 != null) {
      // Collect this frame into the current sign clip.
      _framesAbsent = 0;
      _overlayMisses = 0;
      if (_frameBuffer.length >= _maxFramesBuffer) _frameBuffer.removeAt(0);
      _frameBuffer.add(frame.landmarks180!);
      setState(() {
        _lastHands = frame.overlayHands;
        _lastModelLandmarks = frame.landmarks180;
        _handDetected = true;
      });
    } else {
      // No hands this frame — maybe the sign just ended.
      _framesAbsent++;
      _overlayMisses++;
      if (_handDetected && _overlayMisses > _overlayMissGraceFrames) {
        setState(() {
          _lastHands = const [];
          _lastModelLandmarks = null;
          _handDetected = false;
        });
      }
      if (_frameBuffer.length >= _minFramesForSign &&
          _framesAbsent >= _framesAbsentToPredict) {
        _runPrediction();
      }
    }
  }

  void _handleFingerspellingFrame(NativeFrameResult frame) {
    final rawHand = frame.rightHand ?? frame.leftHand;
    if (!frame.hasHands || rawHand == null || rawHand.length != 63) {
      _framesWithoutHands++;
      if (_framesWithoutHands >= 3) {
        final hadState =
            _lastHands.isNotEmpty ||
            _latchedLetter != null ||
            _letterVotes.isNotEmpty;
        _letterVotes.clear();
        _latchedLetter = null;
        if (hadState) {
          setState(() {
            _lastHands = const [];
            _lastModelLandmarks = null;
            _handDetected = false;
            _letterCandidate = '—';
            _letterIsConfident = false;
          });
        }
      }
      return;
    }

    _framesWithoutHands = 0;
    _letterFrameCounter++;
    if (_letterFrameCounter % 3 != 0) {
      if (!_handDetected || _lastHands.isEmpty) {
        setState(() {
          _lastHands = frame.overlayHands;
          _lastModelLandmarks = frame.landmarks180;
          _handDetected = true;
        });
      }
      return;
    }

    final model = _fingerspellingModel;
    if (model == null) {
      setState(() {
        _lastHands = frame.overlayHands;
        _lastModelLandmarks = frame.landmarks180;
        _handDetected = true;
      });
      return;
    }

    try {
      final prediction = model.predict(rawHand);
      _letterCandidate = prediction.letter;
      // Require both a high score and repeated agreement before adding text.
      final confident =
          prediction.score >= _minimumLetterScore &&
          prediction.margin >= _minimumLetterMargin;
      if (confident) {
        _letterVotes.add(prediction.letter);
        if (_letterVotes.length > 6) _letterVotes.removeAt(0);
      } else {
        _letterVotes.clear();
      }

      final agreedVotes = _letterVotes
          .where((letter) => letter == prediction.letter)
          .length;
      final shouldAppend =
          confident && agreedVotes >= 5 && _latchedLetter != prediction.letter;
      setState(() {
        _lastHands = frame.overlayHands;
        _lastModelLandmarks = frame.landmarks180;
        _handDetected = true;
        _letterIsConfident = confident;
        if (shouldAppend) {
          _appendLetter(prediction.letter);
          _latchedLetter = prediction.letter;
          _fingerspellingStatus =
              'Added ${prediction.letter} · lower hand to capture next letter';
        } else {
          _fingerspellingStatus = confident
              ? 'Hold steady · confirming ${prediction.letter}'
              : 'Low match · adjust hand and try again';
        }
      });
    } catch (error) {
      debugPrint('Fingerspelling inference error: $error');
      setState(() => _fingerspellingStatus = 'Could not read this hand shape.');
    }
  }

  void _setRecognitionMode(_RecognitionMode mode) {
    if (_recognitionMode == mode) return;
    setState(() {
      _recognitionMode = mode;
      _resetBuffer();
      _letterVotes.clear();
      _latchedLetter = null;
      _letterCandidate = '—';
      _letterIsConfident = false;
      _framesWithoutHands = 0;
      _framesAbsent = 0;
      _handDetected = false;
      _lastHands = const [];
      _lastModelLandmarks = null;
      _topPreds = const [];
      _label = 'Show one sign to begin';
    });
  }

  void _appendLetter(String letter) {
    final next = '$_sentence$letter';
    _sentenceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _sentence = next;
  }

  void _insertSpace() {
    if (_sentence.isEmpty || _sentence.endsWith(' ')) return;
    setState(() => _appendLetter(' '));
  }

  void _deleteLastCharacter() {
    if (_sentence.isEmpty) return;
    final next = _sentence.substring(0, _sentence.length - 1);
    _sentenceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _sentence = next);
  }

  Future<void> _runPrediction() async {
    final model = _model;
    if (model == null || _isPredicting || _frameBuffer.isEmpty) return;

    _isPredicting = true;
    if (mounted) setState(() => _label = 'Recognizing…');
    // Snapshot + clear so new signing can start immediately.
    final clip = List<List<double>>.from(_frameBuffer);
    _frameBuffer.clear();
    _framesAbsent = 0;

    try {
      // Reshape each flat 540 frame into [180][3].
      final landmarks = clip
          .map(
            (flat) => List.generate(
              180,
              (l) => [flat[l * 3], flat[l * 3 + 1], flat[l * 3 + 2]],
            ),
          )
          .toList();

      final preds = model.predict(landmarks);
      if (!mounted) return;
      setState(() {
        _topPreds = preds;
        if (preds.isNotEmpty) {
          _label = preds.first.word;
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
    final next = _sentence.trim().isEmpty ? word : '${_sentence.trim()} $word';
    _sentenceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _sentence = next;
  }

  void _finishSentence(String punctuation) {
    final text = _sentence.trim();
    if (text.isEmpty) return;
    final body = text.replaceFirst(RegExp(r'[.!?]+$'), '');
    if (body.isEmpty) return;
    final sentence = '${body[0].toUpperCase()}${body.substring(1)}$punctuation';
    _sentenceController.value = TextEditingValue(
      text: sentence,
      selection: TextSelection.collapsed(offset: sentence.length),
    );
    setState(() => _sentence = sentence);
  }

  void _acceptTopPrediction() {
    if (_topPreds.isEmpty) return;
    setState(() => _appendWord(_topPreds.first.word));
  }

  void _removeLastWord() {
    final words = _sentence.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return;
    words.removeLast();
    final next = words.join(' ');
    _sentenceController.text = next;
    setState(() => _sentence = next);
  }

  void _resetBuffer() {
    _frameBuffer.clear();
    _framesAbsent = 0;
    _overlayMisses = 0;
  }

  void _showQuickGuide() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _recognitionMode == _RecognitionMode.words
                    ? 'Recognize one sign'
                    : 'Spell a message',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              const _GuideStep(
                number: '1',
                text: 'Keep your signing hand in view of the camera.',
              ),
              if (_recognitionMode == _RecognitionMode.words) ...[
                const _GuideStep(
                  number: '2',
                  text:
                      'Sign one word at a time. Tap “Recognize this sign”, then review the suggested word.',
                ),
                const _GuideStep(
                  number: '3',
                  text:
                      'Tap “Add word” if it looks right. You can edit the message at any time.',
                ),
              ] else ...[
                const _GuideStep(
                  number: '2',
                  text:
                      'Hold a handshape steady until a letter is added. Lower your hand briefly before the next letter.',
                ),
                const _GuideStep(
                  number: '3',
                  text:
                      'Use Space between words and the letter keys to correct the message or add any missed letter.',
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _recognitionMode == _RecognitionMode.words
                    ? 'This feature recognizes a limited set of one-word signs and can make mistakes. Check every suggestion before adding it. Use the book icon to learn a sign.'
                    : 'The camera recognizes most still letter shapes. Some letters involve movement and may need to be typed. Check and correct the message as you go.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFingerspellingControls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text(
                _letterIsConfident ? _letterCandidate : '…',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_fingerspellingStatus)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Hold each handshape still. Use the keys for any letter the camera misses.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 7),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 0,
          children: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').map((letter) {
            final motionLetter = letter == 'J' || letter == 'Z';
            return ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(letter),
              tooltip: motionLetter
                  ? '$letter requires movement; add it manually'
                  : 'Insert $letter manually',
              onPressed: () => setState(() => _appendLetter(letter)),
              backgroundColor: motionLetter
                  ? colors.tertiaryContainer
                  : colors.surfaceContainerHighest,
            );
          }).toList(),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            TextButton.icon(
              onPressed: _insertSpace,
              icon: const Icon(Icons.space_bar_rounded),
              label: const Text('Space'),
            ),
            TextButton.icon(
              onPressed: _deleteLastCharacter,
              icon: const Icon(Icons.backspace_outlined),
              label: const Text('Delete'),
            ),
            TextButton.icon(
              onPressed: () {
                _sentenceController.clear();
                setState(() => _sentence = '');
              },
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
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
    _fingerspellingModel?.dispose();
    _sentenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _cameraController?.value.isInitialized == true
        ? CameraPreview(_cameraController!)
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_userStatus, textAlign: TextAlign.center),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign to Text'),
        actions: [
          IconButton(
            tooltip: 'How to test a sign',
            onPressed: _showQuickGuide,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            tooltip: 'Learn ASL signs by video',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AslDictionaryScreen(),
              ),
            ),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: _cameraRunning ? 'Pause camera' : 'Start camera',
            onPressed: _isSwitchingCamera ? null : _toggleCamera,
            icon: Icon(_cameraRunning ? Icons.pause_circle : Icons.play_circle),
          ),
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
            flex: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (_lastModelLandmarks != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LandmarksPainter(
                          landmarks: _lastModelLandmarks!,
                          showUpperBodyAndFace:
                              _recognitionMode == _RecognitionMode.words,
                          mirror:
                              _activeCamera?.lensDirection ==
                              CameraLensDirection.front,
                        ),
                      ),
                    ),
                  ),
                if (_lastModelLandmarks != null &&
                    _recognitionMode == _RecognitionMode.words)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Text(
                          'Model input · Hands 42 · Upper body 6 · Face 132',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_sentence.trim().isNotEmpty &&
                    _recognitionMode == _RecognitionMode.words)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sentence: $_sentence',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_topPreds.isNotEmpty &&
                    _recognitionMode == _RecognitionMode.words)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.94),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.translate_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Possible word: ${_topPreds.first.word}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add word to sentence',
                              onPressed: _acceptTopPrediction,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_cameraRunning &&
                    _cameraController?.value.isInitialized == true)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          'Camera paused',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SegmentedButton<_RecognitionMode>(
                    segments: const [
                      ButtonSegment(
                        value: _RecognitionMode.words,
                        label: Text('Recognize words'),
                        icon: Icon(Icons.text_fields_rounded),
                      ),
                      ButtonSegment(
                        value: _RecognitionMode.fingerspelling,
                        label: Text('Spell by hand'),
                        icon: Icon(Icons.spellcheck_rounded),
                      ),
                    ],
                    selected: {_recognitionMode},
                    onSelectionChanged: (selection) =>
                        _setRecognitionMode(selection.first),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _userStatus,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _handDetected
                            ? Icons.back_hand_rounded
                            : Icons.back_hand_outlined,
                        color: _handDetected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_recognitionMode == _RecognitionMode.words)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'Sign one word at a time, then tap below to see a suggestion.',
                              style: TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_recognitionMode == _RecognitionMode.words) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _model != null &&
                                !_isPredicting &&
                                _frameBuffer.length >= _minFramesForSign
                            ? _runPrediction
                            : null,
                        icon: _isPredicting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.center_focus_strong_rounded),
                        label: Text(
                          _isPredicting
                              ? 'Recognizing…'
                              : 'Recognize this sign',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_topPreds.isEmpty)
                      Text(
                        _userPredictionLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Possible match',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        _userPredictionLabel,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (_topPreds.isNotEmpty)
                      Tooltip(
                        message: 'Add the top prediction to the sentence',
                        child: TextButton.icon(
                          onPressed: _acceptTopPrediction,
                          icon: const Icon(Icons.add),
                          label: Text('Add word · ${_topPreds.first.word}'),
                        ),
                      ),
                    if (_topPreds.length > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Other suggestions: ${_topPreds.skip(1).take(4).map((p) => p.word).join(', ')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    _buildFingerspellingControls(context),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Build a sentence',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_recognitionMode == _RecognitionMode.words)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'Add each confirmed word in signing order, edit as needed, then finish with punctuation.',
                          style: TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: TextField(
                      controller: _sentenceController,
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (value) => setState(() => _sentence = value),
                      decoration: const InputDecoration(
                        hintText: 'Recognized text appears here',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_recognitionMode == _RecognitionMode.words)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: _sentence.trim().isEmpty
                                ? null
                                : () => _finishSentence('.'),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Finish sentence'),
                          ),
                          TextButton(
                            onPressed: _sentence.trim().isEmpty
                                ? null
                                : () => _finishSentence('?'),
                            child: const Text('Question ?'),
                          ),
                          TextButton(
                            onPressed: _sentence.trim().isEmpty
                                ? null
                                : () => _finishSentence('!'),
                            child: const Text('Exclamation !'),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _recognitionMode == _RecognitionMode.words
                            ? _removeLastWord
                            : _deleteLastCharacter,
                        icon: const Icon(Icons.backspace_outlined),
                        label: Text(
                          _recognitionMode == _RecognitionMode.words
                              ? 'Undo last word'
                              : 'Delete last letter',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _sentenceController.clear();
                          setState(() => _sentence = '');
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear text'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _sentenceController.clear();
                          setState(() {
                            _resetBuffer();
                            _lastHands = const [];
                            _lastModelLandmarks = null;
                            _label = 'Show one sign to begin';
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Text(number, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}
