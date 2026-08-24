# Implementation Plan: stt_arena

Flutter app untuk membandingkan 2 library speech-to-text (Bahasa Indonesia) secara side-by-side. Ada 2 tombol mic di AppBar (kiri & kanan), masing-masing memicu library berbeda, transkrip ditampilkan berdampingan.

Project sudah dibuat dengan `flutter create --empty stt_arena`. Plan ini mengasumsikan working directory adalah root project tersebut.

---

## 0. Tujuan & Scope

- Bandingkan **speech_to_text** (csdcorp, v7.4.0) vs **flutter_speech_to_text** (JeromeGsq, v1.2.1) untuk transkripsi Bahasa Indonesia (`id-ID` / `id_ID`).
- Mic kiri di AppBar → trigger `speech_to_text` (sebut: **Engine A**).
- Mic kanan di AppBar → trigger `flutter_speech_to_text` (sebut: **Engine B**).
- Body menampilkan 2 card berdampingan: transkrip Engine A dan Engine B.
- Tidak perlu backend, tidak perlu state management library eksternal — cukup `StatefulWidget` + `ChangeNotifier` sederhana atau `setState` biasa (project kecil, scope eksperimen).
- Target platform utama: **Android** dan **iOS** (Windows/macOS/Web opsional, tidak perlu digarap deep untuk versi pertama).

---

## 1. Dependencies

Edit `pubspec.yaml`, tambahkan di bagian `dependencies:`

```yaml
dependencies:
  flutter:
    sdk: flutter
  speech_to_text: ^7.4.0
  flutter_speech_to_text: ^1.2.1
  permission_handler: ^11.3.1
```

Lalu jalankan:

```bash
flutter pub get
```

Catatan: `permission_handler` opsional tapi disarankan untuk cek status mic permission secara eksplisit sebelum memanggil kedua service, supaya UX-nya konsisten di kedua engine (flutter_speech_to_text sudah punya `requestPermissions()` bawaan, tapi speech_to_text mengandalkan permission dari OS dialog saat `initialize()` — lebih enak kalau dicek manual dulu pakai permission_handler biar behavior-nya seragam).

---

## 2. Native Setup

### 2.1 Android — `android/app/src/main/AndroidManifest.xml`

Tambahkan di dalam tag `<manifest>`, sebelum tag `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>

<queries>
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
</queries>
```

Pastikan `android/app/build.gradle` (atau `build.gradle.kts`):

```
minSdkVersion 21 (atau lebih tinggi)
compileSdkVersion 34 (atau lebih tinggi, minimal 31)
```

### 2.2 iOS — `ios/Runner/Info.plist`

Tambahkan sebelum `</dict>` penutup terakhir:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>Aplikasi ini butuh akses speech recognition untuk mengubah suara menjadi teks.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Aplikasi ini butuh akses mikrofon untuk merekam suara Anda.</string>
```

---

## 3. Struktur Folder

```
lib/
├── main.dart
├── models/
│   └── stt_result.dart
├── services/
│   ├── engine_a_service.dart   # wrapper speech_to_text
│   └── engine_b_service.dart   # wrapper flutter_speech_to_text
└── screens/
    └── home_screen.dart
```

---

## 4. `lib/models/stt_result.dart`

Model transkrip yang seragam dipakai oleh kedua engine, supaya UI tidak perlu tahu detail internal masing-masing plugin.

```dart
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
```

---

## 5. `lib/services/engine_a_service.dart` (speech_to_text / csdcorp)

```dart
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/stt_result.dart';

const String kIndonesianLocaleA = 'id_ID';

class EngineAService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onStatus: (status) => print('EngineA status: $status'),
      onError: (error) => print('EngineA error: ${error.errorMsg}'),
    );
    return _isInitialized;
  }

  /// Cek apakah locale Indonesia tersedia di device ini.
  /// Return true kalau tersedia, false kalau tidak (device perlu
  /// download language pack dulu lewat pengaturan Google App).
  Future<bool> isIndonesianAvailable() async {
    if (!_isInitialized) await initialize();
    final locales = await _speech.locales();
    return locales.any((l) => l.localeId == kIndonesianLocaleA);
  }

  Future<void> startListening({
    required void Function(SttResult result) onResult,
    required void Function(String error) onError,
  }) async {
    final available = await initialize();
    if (!available) {
      onError('Speech recognition tidak tersedia di device ini.');
      return;
    }

    final hasId = await isIndonesianAvailable();
    if (!hasId) {
      onError(
        'Locale id_ID tidak ditemukan di device. '
        'Install language pack Indonesia lewat Settings > Google App > Voice.',
      );
      return;
    }

    await _speech.listen(
      localeId: kIndonesianLocaleA,
      onResult: (SpeechRecognitionResult result) {
        onResult(SttResult(
          transcript: result.recognizedWords,
          confidence: result.confidence,
          isFinal: result.finalResult,
        ));
      },
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
```

---

## 6. `lib/services/engine_b_service.dart` (flutter_speech_to_text / JeromeGsq)

```dart
import 'dart:async';
import 'package:flutter_speech_to_text/flutter_speech_to_text.dart' as fstt;
import '../models/stt_result.dart';

const String kIndonesianLocaleB = 'id-ID';

class EngineBService {
  final fstt.SpeechToText _speech = fstt.SpeechToText();
  StreamSubscription? _resultSub;
  StreamSubscription? _errorSub;
  bool _isListening = false;

  Future<void> startListening({
    required void Function(SttResult result) onResult,
    required void Function(String error) onError,
  }) async {
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

    _resultSub?.cancel();
    _errorSub?.cancel();

    _resultSub = _speech.onResult.listen((result) {
      onResult(SttResult(
        transcript: result.transcript,
        confidence: result.confidence,
        isFinal: result.isFinal,
      ));
    });

    _errorSub = _speech.onError.listen((error) {
      onError('${error.errorCode}: ${error.message}');
      _isListening = false;
    });

    _speech.onEnd.listen((_) {
      _isListening = false;
    });

    await _speech.start(language: kIndonesianLocaleB);
    _isListening = true;
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  void dispose() {
    _resultSub?.cancel();
    _errorSub?.cancel();
    _speech.dispose();
  }

  bool get isListening => _isListening;
}
```

---

## 7. `lib/screens/home_screen.dart`

```dart
import 'package:flutter/material.dart';
import '../models/stt_result.dart';
import '../services/engine_a_service.dart';
import '../services/engine_b_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EngineAService _engineA = EngineAService();
  final EngineBService _engineB = EngineBService();

  String _transcriptA = '';
  String _transcriptB = '';
  String? _errorA;
  String? _errorB;
  bool _listeningA = false;
  bool _listeningB = false;

  Future<void> _toggleEngineA() async {
    if (_listeningA) {
      await _engineA.stopListening();
      setState(() => _listeningA = false);
      return;
    }

    setState(() {
      _errorA = null;
      _listeningA = true;
    });

    await _engineA.startListening(
      onResult: (SttResult result) {
        setState(() => _transcriptA = result.transcript);
      },
      onError: (String error) {
        setState(() {
          _errorA = error;
          _listeningA = false;
        });
      },
    );
  }

  Future<void> _toggleEngineB() async {
    if (_listeningB) {
      await _engineB.stopListening();
      setState(() => _listeningB = false);
      return;
    }

    setState(() {
      _errorB = null;
      _listeningB = true;
    });

    await _engineB.startListening(
      onResult: (SttResult result) {
        setState(() => _transcriptB = result.transcript);
      },
      onError: (String error) {
        setState(() {
          _errorB = error;
          _listeningB = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _engineB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _listeningA ? Icons.mic : Icons.mic_none,
            color: _listeningA ? Colors.red : null,
          ),
          tooltip: 'Engine A (speech_to_text)',
          onPressed: _toggleEngineA,
        ),
        title: const Text('STT Arena'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _listeningB ? Icons.mic : Icons.mic_none,
              color: _listeningB ? Colors.red : null,
            ),
            tooltip: 'Engine B (flutter_speech_to_text)',
            onPressed: _toggleEngineB,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: _EngineCard(
                title: 'Engine A — speech_to_text',
                transcript: _transcriptA,
                error: _errorA,
                isListening: _listeningA,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EngineCard(
                title: 'Engine B — flutter_speech_to_text',
                transcript: _transcriptB,
                error: _errorB,
                isListening: _listeningB,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  final String title;
  final String transcript;
  final String? error;
  final bool isListening;

  const _EngineCard({
    required this.title,
    required this.transcript,
    required this.error,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (isListening)
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.red, size: 12),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  transcript.isEmpty ? '(belum ada hasil)' : transcript,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

---

## 8. `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const SttArenaApp());
}

class SttArenaApp extends StatelessWidget {
  const SttArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STT Arena',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
```

---

## 9. Urutan Eksekusi untuk Claude Code

1. Jalankan `flutter pub get` setelah `pubspec.yaml` diupdate (langkah 1).
2. Terapkan perubahan native di `AndroidManifest.xml` dan `Info.plist` (langkah 2).
3. Buat folder `models/`, `services/`, `screens/` di dalam `lib/`.
4. Buat file sesuai isi di langkah 4–8 di atas, persis seperti kode yang diberikan.
5. Hapus/timpa `lib/main.dart` bawaan `flutter create --empty` dengan versi di langkah 8.
6. Jalankan `flutter analyze` untuk pastikan tidak ada error import/nama collision.
7. Jalankan `flutter run` di device fisik Android (emulator sering tidak reliable untuk speech recognition, terutama untuk Engine A yang butuh Google Speech Services aktif).

---

## 10. Testing Checklist (manual, di device fisik)

- [ ] Tekan mic kiri (Engine A) → ucapkan kalimat Bahasa Indonesia → transkrip muncul di card kiri.
- [ ] Tekan mic kanan (Engine B) → ucapkan kalimat sama → transkrip muncul di card kanan.
- [ ] Bandingkan akurasi transkrip kedua engine untuk kalimat yang sama.
- [ ] Cek behavior saat permission mic ditolak — pastikan `_errorA` / `_errorB` muncul dengan pesan yang jelas, bukan crash.
- [ ] Cek behavior kalau device belum punya language pack Indonesia (Engine A akan kasih pesan eksplisit lewat `isIndonesianAvailable()`; Engine B baru ketahuan lewat `onError` stream).
- [ ] Tes tekan mic saat sedang listening (toggle stop) — pastikan `isListening` ke-reset dengan benar di kedua engine.
- [ ] Tes berpindah dari Engine A ke Engine B tanpa stop dulu (edge case) — pastikan tidak saling mengganggu resource mic.

---

## 11. Known Caveats

- **speech_to_text** hanya didesain untuk command/short phrase, bukan continuous dictation panjang — akan auto-stop setelah jeda diam (~5 detik tergantung device).
- **flutter_speech_to_text** masih versi awal (1.2.1, "vibe coded" dari port React Native per README resminya), publisher belum verified di pub.dev — kemungkinan ada bug/edge case yang belum ditemukan komunitas. Siapkan expektasi kalau ini yang lebih sering error saat testing.
- Kedua plugin sama-sama pakai speech recognizer bawaan OS (Android SpeechRecognizer / iOS Speech Framework) — akurasi Bahasa Indonesia bergantung ke kualitas recognizer Google/Apple di device tersebut, bukan ke kode plugin itu sendiri.
- Jangan jalankan Engine A dan Engine B secara bersamaan (dua mic aktif sekaligus) — kemungkinan besar akan rebutan resource microphone di level OS dan salah satu akan gagal silent.
