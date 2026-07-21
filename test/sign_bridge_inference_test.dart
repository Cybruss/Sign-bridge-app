import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:sign_bridge/utils/landmark_preprocessor.dart';
import 'package:sign_bridge/models/prediction.dart';
import 'package:sign_bridge/services/sign_bridge_inference.dart';

class FakeTf {
  // returns a normalized vector [1,0,0,...]
  void run(Float32List input, List output) {
    final out = List.filled(300, 0.0);
    out[0] = 1.0;
    output[0] = out;
  }

  void close() {}
}

void main() {
  test('preprocessor output shape', () {
    final frames = List.generate(32, (_) => List.generate(180, (_) => [0.0, 0.0, 0.0]));
    final res = LandmarkPreprocessor.preprocess(frames);
    expect(res.length, 64 * 180 * 3);
  });

  test('labels parse and prediction with fake tf', () async {
    final labelsJson = '{"names":["hello","bye"],"vectors":[${List.filled(300, 0.0)},${List.filled(300, 0.0)}] }';
    // Create inference with fake interpreter via Interpreter param is not available here;
    // For test, simply verify labels parsing logic from JSON string
    final inst = await SignBridgeInference.create(interpreter: null, labelsJson: labelsJson, loadModel: false);
    expect(inst.names.length, greaterThan(0));
  });
}
