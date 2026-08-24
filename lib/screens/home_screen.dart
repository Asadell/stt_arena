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
  double? _confidenceA;
  double? _confidenceB;
  String? _errorA;
  String? _errorB;
  String? _statusA;
  bool _listeningA = false;
  bool _listeningB = false;

  @override
  void initState() {
    super.initState();
    _engineA.onStatusChange = (status) {
      if (!mounted) return;
      setState(() {
        _statusA = status;
        // Plugin mengirim 'done'/'notListening' saat sesi berhenti sendiri
        // (silence timeout), jadi tombol mic ikut reset.
        if (status == 'done' || status == 'notListening') _listeningA = false;
      });
    };
    _engineA.onEngineError = (error) {
      if (!mounted) return;
      setState(() {
        _errorA = error;
        _listeningA = false;
      });
    };
    _engineB.onEnd = () {
      if (!mounted) return;
      setState(() => _listeningB = false);
    };
  }

  Future<void> _toggleEngineA() async {
    if (_listeningA) {
      await _engineA.stopListening();
      setState(() => _listeningA = false);
      return;
    }

    // Hindari dua mic aktif sekaligus -- rebutan resource di level OS.
    if (_listeningB) {
      await _engineB.stopListening();
      setState(() => _listeningB = false);
    }

    setState(() {
      _errorA = null;
      _statusA = null;
      _transcriptA = '';
      _confidenceA = null;
      _listeningA = true;
    });

    await _engineA.startListening(
      onResult: (SttResult result) {
        if (!mounted) return;
        setState(() {
          _transcriptA = result.transcript;
          _confidenceA = result.confidence;
        });
      },
      onError: (String error) {
        if (!mounted) return;
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

    if (_listeningA) {
      await _engineA.stopListening();
      setState(() => _listeningA = false);
    }

    setState(() {
      _errorB = null;
      _transcriptB = '';
      _confidenceB = null;
      _listeningB = true;
    });

    await _engineB.startListening(
      onResult: (SttResult result) {
        if (!mounted) return;
        setState(() {
          _transcriptB = result.transcript;
          _confidenceB = result.confidence;
        });
      },
      onError: (String error) {
        if (!mounted) return;
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
                title: 'Engine A\nspeech_to_text',
                transcript: _transcriptA,
                confidence: _confidenceA,
                status: _statusA,
                error: _errorA,
                isListening: _listeningA,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EngineCard(
                title: 'Engine B\nflutter_speech_to_text',
                transcript: _transcriptB,
                confidence: _confidenceB,
                status: null,
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
  final double? confidence;
  final String? status;
  final String? error;
  final bool isListening;

  const _EngineCard({
    required this.title,
    required this.transcript,
    required this.confidence,
    required this.status,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
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
            if (confidence != null && confidence! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'confidence: ${confidence!.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            if (status != null)
              Text(
                'status: $status',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
