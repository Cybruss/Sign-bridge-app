import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FingerspellingPrediction {
  const FingerspellingPrediction({
    required this.letter,
    required this.score,
    required this.margin,
  });

  final String letter;
  final double score;
  final double margin;
}

/// Compact static ASL fingerspelling classifier, separate from the word model.
/// Input is one 21-point MediaPipe hand normalized at the wrist and palm scale.
class FingerspellingInference {
  FingerspellingInference._(this._interpreter, this.names);

  final Interpreter _interpreter;
  final List<String> names;

  static Future<FingerspellingInference> create() async {
    final options = InterpreterOptions()..threads = 2;
    final modelBytes = await rootBundle.load('assets/ml/fingerspelling.tflite');
    final interpreter = Interpreter.fromBuffer(
      modelBytes.buffer.asUint8List(
        modelBytes.offsetInBytes,
        modelBytes.lengthInBytes,
      ),
      options: options,
    );
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      if (inputShape.length != 2 || inputShape[1] != 63) {
        throw StateError('Unexpected fingerspelling input shape: $inputShape');
      }
      final labels =
          json.decode(
                await rootBundle.loadString(
                  'assets/ml/fingerspelling_labels.json',
                ),
              )
              as Map<String, dynamic>;
      final names = List<String>.from(labels['names'] as List);
      if (outputShape.length != 2 || outputShape[1] != names.length) {
        throw StateError('Output shape $outputShape does not match $names');
      }
      return FingerspellingInference._(interpreter, names);
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  FingerspellingPrediction predict(List<double> handLandmarks) {
    if (handLandmarks.length != 63) {
      throw ArgumentError.value(handLandmarks.length, 'handLandmarks.length');
    }
    final points = List.generate(
      21,
      (index) => [
        handLandmarks[index * 3],
        handLandmarks[index * 3 + 1],
        handLandmarks[index * 3 + 2],
      ],
    );

    final wrist = points[0];
    for (final point in points) {
      for (var axis = 0; axis < 3; axis++) {
        point[axis] -= wrist[axis];
      }
    }
    final palmScale = math.sqrt(
      points[9][0] * points[9][0] + points[9][1] * points[9][1],
    );
    if (!palmScale.isFinite || palmScale < 1e-5) {
      throw StateError('Hand landmarks have an invalid palm scale.');
    }

    final input = [
      points
          .expand((point) => point.map((value) => value / palmScale))
          .toList(),
    ];
    final output = [List<double>.filled(names.length, 0)];
    _interpreter.run(input, output);
    final ranked = List<int>.generate(names.length, (index) => index)
      ..sort((a, b) => output[0][b].compareTo(output[0][a]));
    final bestIndex = ranked.first;
    final margin = output[0][bestIndex] - output[0][ranked[1]];
    return FingerspellingPrediction(
      letter: names[bestIndex],
      score: output[0][bestIndex],
      margin: margin,
    );
  }

  void dispose() => _interpreter.close();
}
