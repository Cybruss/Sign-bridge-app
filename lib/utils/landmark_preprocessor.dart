import 'dart:typed_data';

class LandmarkPreprocessor {
  /// rawFrames: [frames][180][3]
  static Float32List preprocess(List<List<List<double>>> rawFrames) {
    final frames = rawFrames.length;
    // Ensure each frame has 180 landmarks x 3
    final normalized = <List<List<double>>>[];

    for (var f = 0; f < frames; f++) {
      final frame = rawFrames[f];
      // make a deep copy of shape [180][3]
      final copy = List<List<double>>.generate(
        180,
        (i) => List<double>.filled(3, 0.0),
      );
      for (var i = 0; i < 180 && i < frame.length; i++) {
        final lm = frame[i];
        copy[i][0] = lm.isNotEmpty ? lm[0] : 0.0;
        copy[i][1] = lm.length > 1 ? lm[1] : 0.0;
        copy[i][2] = lm.length > 2 ? lm[2] : 0.0;
      }

      // normalize right hand (0-20) by wrist 0
      _normalizeHand(copy, 0, 20);
      // normalize left hand (21-41) by wrist 21
      _normalizeHand(copy, 21, 41);

      normalized.add(copy);
    }

    // Interpolate to 64 frames
    final interp = _interpolateFrames(normalized, 64);

    // Flatten to Float32List [1,64,180,3]
    final out = Float32List(64 * 180 * 3);
    var idx = 0;
    for (var f = 0; f < 64; f++) {
      final frame = interp[f];
      for (var l = 0; l < 180; l++) {
        out[idx++] = frame[l][0].toDouble();
        out[idx++] = frame[l][1].toDouble();
        out[idx++] = frame[l][2].toDouble();
      }
    }

    return out;
  }

  static void _normalizeHand(List<List<double>> frame, int start, int end) {
    if (start >= frame.length) return;
    final wrist = frame[start];
    // compute max abs value across coords in that hand
    double maxAbs = 1e-6;
    for (var i = start; i <= end && i < frame.length; i++) {
      final p = frame[i];
      final dx = p[0] - wrist[0];
      final dy = p[1] - wrist[1];
      final dz = p[2] - wrist[2];
      maxAbs = maxAbs < dx.abs() ? dx.abs() : maxAbs;
      maxAbs = maxAbs < dy.abs() ? dy.abs() : maxAbs;
      maxAbs = maxAbs < dz.abs() ? dz.abs() : maxAbs;
    }
    if (maxAbs < 1e-6) maxAbs = 1.0;
    for (var i = start; i <= end && i < frame.length; i++) {
      final p = frame[i];
      p[0] = (p[0] - wrist[0]) / maxAbs;
      p[1] = (p[1] - wrist[1]) / maxAbs;
      p[2] = (p[2] - wrist[2]) / maxAbs;
    }
  }

  static List<List<List<double>>> _interpolateFrames(
    List<List<List<double>>> frames,
    int target,
  ) {
    final n = frames.length;
    if (n == target) return frames;
    final out = List<List<List<double>>>.generate(
      target,
      (_) => List.generate(180, (_) => [0.0, 0.0, 0.0]),
    );
    if (n == 0) return out;
    for (var t = 0; t < target; t++) {
      final pos = t * (n - 1) / (target - 1);
      final i0 = pos.floor();
      final i1 = pos.ceil();
      final alpha = pos - i0;
      for (var l = 0; l < 180; l++) {
        final a = frames[i0][l];
        final b = frames[i1][l];
        out[t][l][0] = a[0] * (1 - alpha) + b[0] * alpha;
        out[t][l][1] = a[1] * (1 - alpha) + b[1] * alpha;
        out[t][l][2] = a[2] * (1 - alpha) + b[2] * alpha;
      }
    }
    return out;
  }
}
