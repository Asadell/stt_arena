import 'dart:async';
import 'package:flutter_speech_to_text/flutter_speech_to_text.dart' as fstt;
import '../models/stt_result.dart';
import 'mic_permission.dart';

const String kIndonesianLocaleB = 'id-ID';

class EngineBService {
  final fstt.SpeechToText _speech = fstt.SpeechToText();
  StreamSubscription? _resultSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _endSub;
  bool _isListening = false;

  /// Dipanggil saat plugin mengirim event onEnd (sesi berhenti sendiri karena
  /// silence/timeout), supaya tombol mic di UI ikut kembali ke state idle.
  void Function()? onEnd;

  Future<void> startListening({
    required void Function(SttResult result) onResult,
    required void Function(String error) onError,
  }) async {
    final permError = await MicPermission.ensureGranted();
    if (permError != null) {
      onError(permError);
      return;
    }

    final available = await _speech.isAvailable();
    if (!available) {
      onError('Speech recognition tidak tersedia di device ini.');
      return;
    }

    final hasPermission = await _speech.requestPermissions();
    if (!hasPermission) {
      onError('Izin mikrofon/speech recognition ditolak.');
      return;
    }

    await _cancelSubs();

    _resultSub = _speech.onResult.listen((result) {
      onResult(SttResult(
        transcript: result.transcript,
        confidence: result.confidence,
        isFinal: result.isFinal,
      ));
    });

    _errorSub = _speech.onError.listen((error) {
      _isListening = false;
      onError('${error.errorCode.code}: ${error.message}');
    });

    _endSub = _speech.onEnd.listen((_) {
      _isListening = false;
      onEnd?.call();
    });

    try {
      await _speech.start(language: kIndonesianLocaleB);
      _isListening = true;
    } on fstt.SpeechError catch (e) {
      _isListening = false;
      onError('${e.errorCode.code}: ${e.message}');
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  Future<void> _cancelSubs() async {
    await _resultSub?.cancel();
    await _errorSub?.cancel();
    await _endSub?.cancel();
    _resultSub = null;
    _errorSub = null;
    _endSub = null;
  }

  /// Catatan: fstt.SpeechToText() adalah singleton dan dispose()-nya menutup
  /// StreamController global yang tidak pernah dibuat ulang, jadi di sini
  /// cukup batalkan subscription supaya engine masih bisa dipakai lagi.
  void dispose() {
    _cancelSubs();
  }

  bool get isListening => _isListening;
}
