import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/prediction.dart';
import '../utils/landmark_preprocessor.dart';

class _TfWrapper {
  final Interpreter interpreter;
  _TfWrapper(this.interpreter);
  void run(Object input, Object output) => interpreter.run(input, output);
  void close() => interpreter.close();
}

class SignBridgeInference {
  late final _TfWrapper _tf;
  late final List<String> names;
  late final List<List<double>> vectors; // normalized

  SignBridgeInference._();

  static Future<SignBridgeInference> create({Interpreter? interpreter, String? labelsJson, bool loadModel = true}) async {
    final inst = SignBridgeInference._();

    if (loadModel) {
      if (interpreter != null) {
        inst._tf = _TfWrapper(interpreter);
      } else {
        final options = InterpreterOptions()..threads = 4;
        final ip = await Interpreter.fromAsset('assets/ml/sign_bridge.tflite', options: options);
        inst._tf = _TfWrapper(ip);
      }
    }

    final jsonStr = labelsJson ?? await rootBundle.loadString('assets/ml/labels.json');
    final parsed = json.decode(jsonStr) as Map<String, dynamic>;
    inst.names = List<String>.from(parsed['names'] as List);
    final vecs = (parsed['vectors'] as List).map<List<double>>((e) => List<double>.from((e as List).map((x) => (x as num).toDouble()))).toList();
    inst.vectors = vecs;
    return inst;
  }

  Future<List<Prediction>> predict(List<List<List<double>>> landmarks) async {
    final input = LandmarkPreprocessor.preprocess(landmarks);

    final output = List.generate(1, (_) => List.filled(300, 0.0));
    _tf.run(input.buffer.asFloat32List(), output);

    final outVec = List<double>.from(output[0].map((e) => (e as num).toDouble()));

    final preds = <Prediction>[];
    for (var i = 0; i < names.length && i < vectors.length; i++) {
      final labelVec = vectors[i];
      double dot = 0.0;
      for (var k = 0; k < outVec.length && k < labelVec.length; k++) {
        dot += outVec[k] * labelVec[k];
      }
      preds.add(Prediction(names[i], dot.clamp(0.0, 1.0)));
    }

    preds.sort((a, b) => b.confidence.compareTo(a.confidence));
    return preds.take(3).toList();
  }

  void dispose() {
    _tf.close();
  }
}

extension _ListReshape on List {
  List reshape(List<int> shape) {
    return this;
  }
}
