import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One frame of holistic landmarks from the native MediaPipe processor.
class NativeFrameResult {
  /// Flat 180x3 = 540 feature vector in the trained order
  /// (21 right-hand, 21 left-hand, 6 pose, 132 face). Null when no person.
  final List<double>? landmarks180;

  /// Whether at least one hand was detected this frame.
  final bool hasHands;

  /// 21x3 lists for the on-screen overlay (null when the hand is absent).
  final List<double>? rightHand;
  final List<double>? leftHand;

  const NativeFrameResult({
    required this.landmarks180,
    required this.hasHands,
    required this.rightHand,
    required this.leftHand,
  });

  /// Hands for the overlay painter (each 63 long), primary first.
  List<List<double>> get overlayHands => [
    if (rightHand != null) rightHand!,
    if (leftHand != null) leftHand!,
  ];
}

class NativeLandmarkerService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.sign_bridge/landmarker',
  );
  bool _busy = false;

  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLandmarkerAvailable');
      return result == true;
    } catch (e) {
      debugPrint('NativeLandmarkerService.isAvailable error: $e');
      return false;
    }
  }

  Future<NativeFrameResult?> processFrame(
    CameraImage image, {
    required int rotationDegrees,
    required bool isFrontCamera,
  }) async {
    if (_busy) return null;
    _busy = true;
    try {
      final args = <String, Object?>{
        'width': image.width,
        'height': image.height,
        'rotationDegrees': rotationDegrees,
        'isFrontCamera': isFrontCamera,
        'yBytes': Uint8List.fromList(image.planes[0].bytes),
        'uBytes': Uint8List.fromList(image.planes[1].bytes),
        'vBytes': Uint8List.fromList(image.planes[2].bytes),
        'yRowStride': image.planes[0].bytesPerRow,
        'uRowStride': image.planes[1].bytesPerRow,
        'vRowStride': image.planes[2].bytesPerRow,
        'uPixelStride': image.planes[1].bytesPerPixel ?? 1,
        'vPixelStride': image.planes[2].bytesPerPixel ?? 1,
      };

      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'processFrame',
        args,
      );
      if (response == null || response.isEmpty) return null;

      return NativeFrameResult(
        landmarks180: _toDoubles(response['landmarks180']),
        hasHands: response['hasHands'] == true,
        rightHand: _toDoubles(response['rightHand']),
        leftHand: _toDoubles(response['leftHand']),
      );
    } on PlatformException catch (e) {
      debugPrint(
        'NativeLandmarkerService.processFrame platform error: ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('NativeLandmarkerService.processFrame error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  static List<double>? _toDoubles(Object? raw) {
    if (raw is! List) return null;
    return raw.cast<num>().map((v) => v.toDouble()).toList();
  }

  void dispose() {
    _busy = false;
  }
}
