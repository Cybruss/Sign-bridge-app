import 'package:flutter/material.dart';
import 'dart:async';
import 'native_landmarker_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Example showing how to use native landmarks for sign language recognition
class SignLanguageDetector {
  Interpreter? _signModel;
  List<String> _labels = [];
  
  // Buffer for sequence-based models (e.g., 30 frames)
  final List<List<double>> _landmarkBuffer = [];
  final int _sequenceLength = 30;
  
  // Callback for sign detection results
  Function(String sign, double confidence)? onSignDetected;

  /// Initialize the sign language model
  Future<void> initialize({
    required String modelPath,
    required String labelsPath,
  }) async {
    try {
      // Load TFLite model
      _signModel = await Interpreter.fromAsset(modelPath);
      
      // Load labels
      final labelsData = await DefaultAssetBundle.of(
        // You'll need to pass context or use rootBundle
        // For now showing the structure
      ).loadString(labelsPath);
      _labels = labelsData.split('\n').where((l) => l.isNotEmpty).toList();
      
      print('Sign language model loaded: ${_labels.length} classes');
    } catch (e) {
      print('Error loading sign language model: $e');
    }
  }

  /// Process landmarks and detect sign
  Future<void> processLandmarks() async {
    try {
      // Get landmarks from native landmarker
      final landmarks = await NativeLandmarkerService.getLatestLandmarks();
      
      if (landmarks == null || !landmarks.isValidLandmarkList) {
        return; // No valid hand detected
      }

      // Add to buffer for sequence models
      _landmarkBuffer.add(landmarks);
      if (_landmarkBuffer.length > _sequenceLength) {
        _landmarkBuffer.removeAt(0);
      }

      // If buffer is full, run classification
      if (_landmarkBuffer.length == _sequenceLength && _signModel != null) {
        await _classifySign();
      }
    } catch (e) {
      print('Error processing landmarks: $e');
    }
  }

  /// Run sign classification on buffered landmarks
  Future<void> _classifySign() async {
    if (_signModel == null) return;

    try {
      // Flatten the buffer: [sequenceLength, 63] -> [sequenceLength * 63]
      final input = _landmarkBuffer.expand((frame) => frame).toList();
      
      // Prepare input tensor [1, sequenceLength, 63]
      final inputTensor = [input];
      
      // Prepare output tensor
      final outputTensor = List.filled(_labels.length, 0.0).reshape([1, _labels.length]);
      
      // Run inference
      _signModel!.run(inputTensor, outputTensor);
      
      // Get prediction
      final probabilities = outputTensor[0] as List<double>;
      final maxIndex = probabilities.indexOf(probabilities.reduce((a, b) => a > b ? a : b));
      final confidence = probabilities[maxIndex];
      
      // Only report if confidence is high enough
      if (confidence > 0.7 && maxIndex < _labels.length) {
        final detectedSign = _labels[maxIndex];
        onSignDetected?.call(detectedSign, confidence);
      }
    } catch (e) {
      print('Error classifying sign: $e');
    }
  }

  /// Process multiple hands (for two-handed signs)
  Future<void> processMultipleHands() async {
    try {
      final allHands = await NativeLandmarkerService.getAllHandsLandmarks();
      final handCount = await NativeLandmarkerService.getHandCount();
      
      print('Detected $handCount hands');
      
      if (allHands != null && allHands.isNotEmpty) {
        // Process each hand
        for (int i = 0; i < allHands.length; i++) {
          final handLandmarks = allHands[i];
          print('Hand $i: ${handLandmarks.length} values');
          
          // You can combine landmarks from both hands
          // or process them separately depending on your model
        }
        
        // Example: Combine both hands for two-handed signs
        if (allHands.length == 2) {
          final combinedLandmarks = [...allHands[0], ...allHands[1]];
          // Process combined landmarks (126 values for 2 hands)
          _processTwoHandedSign(combinedLandmarks);
        }
      }
    } catch (e) {
      print('Error processing multiple hands: $e');
    }
  }

  /// Process two-handed signs
  void _processTwoHandedSign(List<double> combinedLandmarks) {
    // Add your two-handed sign detection logic here
    // This could use a different model trained on 2-hand data
    print('Processing two-handed sign with ${combinedLandmarks.length} values');
  }

  /// Clean up resources
  void dispose() {
    _signModel?.close();
    _landmarkBuffer.clear();
  }
}

/// Example widget showing real-time sign detection
class SignLanguageDetectionWidget extends StatefulWidget {
  @override
  _SignLanguageDetectionWidgetState createState() => _SignLanguageDetectionWidgetState();
}

class _SignLanguageDetectionWidgetState extends State<SignLanguageDetectionWidget> {
  final SignLanguageDetector _detector = SignLanguageDetector();
  String _currentSign = 'No sign detected';
  double _confidence = 0.0;
  int _handCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _startPolling();
  }

  Future<void> _initializeDetector() async {
    await _detector.initialize(
      modelPath: 'assets/models/sign_language_model.tflite',
      labelsPath: 'assets/models/labels.txt',
    );
    
    _detector.onSignDetected = (sign, confidence) {
      setState(() {
        _currentSign = sign;
        _confidence = confidence;
      });
    };
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(Duration(milliseconds: 100), (timer) async {
      // Update hand count
      final count = await NativeLandmarkerService.getHandCount();
      if (count != _handCount) {
        setState(() => _handCount = count);
      }
      
      // Process landmarks
      if (count > 0) {
        if (count == 1) {
          await _detector.processLandmarks();
        } else {
          await _detector.processMultipleHands();
        }
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Hands Detected: $_handCount',
          style: TextStyle(fontSize: 18),
        ),
        SizedBox(height: 20),
        Text(
          _currentSign,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: _confidence > 0.8 ? Colors.green : Colors.orange,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 16),
        ),
      ],
    );
  }
}
