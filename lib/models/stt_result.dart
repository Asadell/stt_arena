class SttResult {
  final String transcript;
  final double? confidence;
  final bool isFinal;

  const SttResult({
    required this.transcript,
    this.confidence,
    required this.isFinal,
  });
}

enum SttStatus { idle, listening, error }
