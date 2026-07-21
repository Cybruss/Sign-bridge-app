import 'package:flutter/services.dart';

/// Service to interact with native MediaPipe hand landmarker
/// 
/// Provides methods to:
/// - Check if native landmarker is available
/// - Get landmarks for detected hands
/// - Start native camera activity
/// - Access hand count and multiple hands data
class NativeLandmarkerService {
  static const MethodChannel _channel = MethodChannel('com.example.sign_bridge/landmarker');

  /// Check if native hand landmarker is available
  static Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLandmarkerAvailable');
      return result ?? false;
    } catch (e) {
      print('Error checking landmarker availability: $e');
      return false;
    }
  }

  /// Get landmarks for the first detected hand
  /// Returns List<double> with 63 values (21 landmarks × 3 coordinates: x, y, z)
  /// Returns null if no hand is detected
  static Future<List<double>?> getLatestLandmarks() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getLatestLandmarks');
      return result?.cast<double>();
    } catch (e) {
      print('Error getting latest landmarks: $e');
      return null;
    }
  }

  /// Get landmarks for all detected hands
  /// Returns List<List<double>> where each inner list has 63 values (21 landmarks × 3 coordinates)
  /// Returns null if no hands are detected
  static Future<List<List<double>>?> getAllHandsLandmarks() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAllHandsLandmarks');
      if (result == null) return null;
      
      return result.map((handData) {
        if (handData is List) {
          return handData.cast<double>();
        }
        return <double>[];
      }).toList();
    } catch (e) {
      print('Error getting all hands landmarks: $e');
      return null;
    }
  }

  /// Get the number of currently detected hands
  static Future<int> getHandCount() async {
    try {
      final result = await _channel.invokeMethod<int>('getHandCount');
      return result ?? 0;
    } catch (e) {
      print('Error getting hand count: $e');
      return 0;
    }
  }

  /// Clear stored landmarks
  static Future<bool> clearLandmarks() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearLandmarks');
      return result ?? false;
    } catch (e) {
      print('Error clearing landmarks: $e');
      return false;
    }
  }

  /// Start the native camera activity with hand detection
  static Future<bool> startNativeLandmarker() async {
    try {
      final result = await _channel.invokeMethod<bool>('startNativeLandmarker');
      return result ?? false;
    } catch (e) {
      print('Error starting native landmarker: $e');
      return false;
    }
  }

  /// Convert landmarks to a format suitable for sign language model
  /// Input: List<double> with 63 values (21 landmarks × 3 coordinates)
  /// Output: Flattened list ready for model input
  static List<double> formatForModel(List<double> landmarks) {
    if (landmarks.length != 63) {
      throw ArgumentError('Expected 63 landmark values (21 landmarks × 3), got ${landmarks.length}');
    }
    return landmarks;
  }

  /// Extract specific landmark by index (0-20)
  /// Returns [x, y, z] coordinates
  static List<double> getLandmark(List<double> landmarks, int index) {
    if (index < 0 || index >= 21) {
      throw ArgumentError('Landmark index must be between 0 and 20');
    }
    if (landmarks.length != 63) {
      throw ArgumentError('Expected 63 landmark values');
    }
    
    final baseIndex = index * 3;
    return [
      landmarks[baseIndex],     // x
      landmarks[baseIndex + 1], // y
      landmarks[baseIndex + 2], // z
    ];
  }

  /// Get all 21 landmarks as List<List<double>> where each inner list is [x, y, z]
  static List<List<double>> parseLandmarks(List<double> landmarks) {
    if (landmarks.length != 63) {
      throw ArgumentError('Expected 63 landmark values');
    }
    
    return List.generate(21, (i) => getLandmark(landmarks, i));
  }
}

/// Extension methods for convenient landmark access
extension LandmarkListExtension on List<double> {
  /// Check if this is a valid landmark list (63 values)
  bool get isValidLandmarkList => length == 63;

  /// Get landmark at index as [x, y, z]
  List<double> getLandmarkAt(int index) {
    return NativeLandmarkerService.getLandmark(this, index);
  }

  /// Parse all landmarks as List<List<double>>
  List<List<double>> get asLandmarks {
    return NativeLandmarkerService.parseLandmarks(this);
  }
}
