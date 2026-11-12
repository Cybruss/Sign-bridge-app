import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sign_bridge/utils/landmark_preprocessor.dart';
import 'package:sign_bridge/models/prediction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preprocessor resizes any clip to 64 frames', () {
    final frames = List.generate(
      32,
      (_) => List.generate(180, (_) => [0.0, 0.0, 0.0]),
    );
    final res = LandmarkPreprocessor.preprocess(frames);
    expect(res.length, 64 * 180 * 3);
  });

  test('preprocessor handles a short clip', () {
    final frames = List.generate(
      5,
      (_) => List.generate(180, (_) => [0.1, 0.2, 0.3]),
    );
    final res = LandmarkPreprocessor.preprocess(frames);
    expect(res.length, 64 * 180 * 3);
  });

  test('preprocessor represents an empty clip as a fixed zero sequence', () {
    final res = LandmarkPreprocessor.preprocess(const []);
    expect(res.length, 64 * 180 * 3);
    expect(res.every((value) => value == 0), isTrue);
  });

  test('bundled label vectors match the embedding output contract', () async {
    final jsonText = await rootBundle.loadString('assets/ml/labels.json');
    final labels = jsonDecode(jsonText) as Map<String, dynamic>;
    final names = List<String>.from(labels['names'] as List);
    final vectors = labels['vectors'] as List;

    expect(names, hasLength(351));
    expect(names.toSet(), hasLength(names.length));
    expect(vectors, hasLength(names.length));
    expect(vectors.every((vector) => (vector as List).length == 300), isTrue);
  });

  test('prediction confidence formatting', () {
    final p = Prediction('hello', 0.873);
    expect(p.word, 'hello');
    expect(p.toString(), contains('87.3%'));
  });
}
