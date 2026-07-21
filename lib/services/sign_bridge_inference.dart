import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/prediction.dart';
import '../utils/landmark_preprocessor.dart';

/// Runs the Sign Bridge GRU model (`sign_bridge.tflite`).
///
/// Input : [1, 64, 180, 3] float32 (preprocessed landmark sequence)
/// Output: [1, 300]        L2-normalized word embedding
/// Words are ranked by cosine similarity against the vectors in labels.json.
class SignBridgeInference {
  final Interpreter _interpreter;
  final List<String> names;
  final List<List<double>> vectors; // L2-normalized label embeddings

  SignBridgeInference._(this._interpreter, this.names, this.vectors);

  static const int _frames = 64;
  static const int _landmarks = 180;
  static const int _coords = 3;
  static const int _outputDim = 300;

  static Future<SignBridgeInference> create({
    String modelAsset = 'assets/ml/sign_bridge.tflite',
    String labelsAsset = 'assets/ml/labels.json',
  }) async {
    final options = InterpreterOptions()..threads = 4;

    // Load via bytes so asset-path packaging quirks don't bite us.
    final modelBytes = await rootBundle.load(modelAsset);
    final interpreter =
        Interpreter.fromBuffer(modelBytes.buffer.asUint8List(), options: options);

    final jsonStr = await rootBundle.loadString(labelsAsset);
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    final names = List<String>.from(parsed['names'] as List);
    final vectors = (parsed['vectors'] as List)
        .map<List<double>>(
            (e) => (e as List).map((x) => (x as num).toDouble()).toList())
        .toList();

    return SignBridgeInference._(interpreter, names, vectors);
  }

  /// [landmarks] is [frames][180][3] (any frame count; resized to 64 internally).
  /// Returns the top-3 predicted words with cosine-similarity confidence.
  List<Prediction> predict(List<List<List<double>>> landmarks) {
    final flat = LandmarkPreprocessor.preprocess(landmarks); // Float32List 64*180*3

    // Reshape flat buffer into the [1,64,180,3] nested structure tflite_flutter wants.
    var i = 0;
    final input = List.generate(
      1,
      (_) => List.generate(
        _frames,
        (_) => List.generate(
          _landmarks,
          (_) => List.generate(_coords, (_) => flat[i++].toDouble()),
        ),
      ),
    );

    final output = List.generate(1, (_) => List.filled(_outputDim, 0.0));
    _interpreter.run(input, output);

    final outVec = output[0];

    final preds = <Prediction>[];
    for (var n = 0; n < names.length && n < vectors.length; n++) {
      final labelVec = vectors[n];
      double dot = 0.0;
      for (var k = 0; k < outVec.length && k < labelVec.length; k++) {
        dot += outVec[k] * labelVec[k];
      }
      // Both vectors are L2-normalized, so dot == cosine similarity in [-1, 1].
      preds.add(Prediction(names[n], dot.clamp(0.0, 1.0)));
    }

    preds.sort((a, b) => b.confidence.compareTo(a.confidence));
    return preds.take(3).toList();
  }

  void dispose() {
    _interpreter.close();
  }
}
