class Prediction {
  final String word;
  final double confidence;

  Prediction(this.word, this.confidence);

  @override
  String toString() => '$word (${(confidence * 100).toStringAsFixed(1)}%)';
}
