import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeFrameResult {
  final List<double>? primaryLandmarks;
  final List<List<double>> allHands;

  const NativeFrameResult({
    required this.primaryLandmarks,
    required this.allHands,
  });
}

class NativeLandmarkerService {
  static const MethodChannel _channel = MethodChannel('com.example.sign_bridge/landmarker');
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

      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>('processFrame', args);
      if (response == null) return null;

      final primaryRaw = response['landmarks'] as List<dynamic>?;
      final allHandsRaw = response['allHands'] as List<dynamic>?;

      final primary = primaryRaw?.cast<num>().map((value) => value.toDouble()).toList();
      final allHands = (allHandsRaw ?? const <dynamic>[])
          .map((hand) => (hand as List<dynamic>).cast<num>().map((value) => value.toDouble()).toList())
          .toList();

      return NativeFrameResult(
        primaryLandmarks: primary,
        allHands: allHands,
      );
    } on PlatformException catch (e) {
      debugPrint('NativeLandmarkerService.processFrame platform error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('NativeLandmarkerService.processFrame error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _busy = false;
  }
}
