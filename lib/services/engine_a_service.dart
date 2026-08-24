import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/stt_result.dart';
import 'mic_permission.dart';

const String kIndonesianLocaleA = 'id_ID';

class EngineAService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  String? _resolvedLocaleId;

  /// Dipanggil UI supaya status/error dari plugin (yang datang async, di luar
  /// callback onResult) tetap kelihatan di card.
  void Function(String status)? onStatusChange;
  void Function(String error)? onEngineError;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onStatus: (status) => onStatusChange?.call(status),
      onError: (error) => onEngineError?.call(error.errorMsg),
    );
    return _isInitialized;
  }

  /// Cari locale Indonesia yang benar-benar dilaporkan device.
  /// Android kadang memakai kode legacy `in_ID` (Java Locale) alih-alih
  /// `id_ID`, jadi keduanya diterima. Null berarti device belum punya
  /// language pack Indonesia.
  Future<String?> resolveIndonesianLocale() async {
    if (_resolvedLocaleId != null) return _resolvedLocaleId;
    if (!_isInitialized) await initialize();
    final locales = await _speech.locales();
    for (final l in locales) {
      final id = l.localeId.replaceAll('-', '_').toLowerCase();
      if (id == 'id_id' || id == 'in_id' || id == 'id' || id == 'in') {
        _resolvedLocaleId = l.localeId;
        return _resolvedLocaleId;
      }
    }
    return null;
  }

  Future<bool> isIndonesianAvailable() async =>
      (await resolveIndonesianLocale()) != null;

  Future<void> startListening({
    required void Function(SttResult result) onResult,
    required void Function(String error) onError,
  }) async {
    final permError = await MicPermission.ensureGranted();
    if (permError != null) {
      onError(permError);
      return;
    }

    final available = await initialize();
    if (!available) {
      onError('Speech recognition tidak tersedia di device ini.');
      return;
    }

    final localeId = await resolveIndonesianLocale();
    if (localeId == null) {
      onError(
        'Locale id_ID tidak ditemukan di device. '
        'Install language pack Indonesia lewat Settings > Google App > Voice.',
      );
      return;
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult(SttResult(
          transcript: result.recognizedWords,
          confidence: result.confidence,
          isFinal: result.finalResult,
        ));
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
