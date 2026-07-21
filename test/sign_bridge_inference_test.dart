import 'package:flutter_test/flutter_test.dart';

import 'package:sign_bridge/utils/landmark_preprocessor.dart';
import 'package:sign_bridge/models/prediction.dart';

void main() {
  test('preprocessor resizes any clip to 64 frames', () {
    final frames =
        List.generate(32, (_) => List.generate(180, (_) => [0.0, 0.0, 0.0]));
    final res = LandmarkPreprocessor.preprocess(frames);
    expect(res.length, 64 * 180 * 3);
  });

  test('preprocessor handles a short clip', () {
    final frames =
        List.generate(5, (_) => List.generate(180, (_) => [0.1, 0.2, 0.3]));
    final res = LandmarkPreprocessor.preprocess(frames);
    expect(res.length, 64 * 180 * 3);
  });

  test('prediction confidence formatting', () {
    final p = Prediction('hello', 0.873);
    expect(p.word, 'hello');
    expect(p.toString(), contains('87.3%'));
  });
}
