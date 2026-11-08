import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/discord_colors.dart';
import '../../../core/services/storage_service.dart';

class VoiceRecordDialog extends StatefulWidget {
  final Function(Uint8List audioBytes, {String extension, String mimeType}) onSendAudio;

  const VoiceRecordDialog({
    super.key,
    required this.onSendAudio,
  });

  @override
  State<VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<VoiceRecordDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  bool _isRecording = false;
  String? _recordedFilePath;

  static const int maxDurationSeconds = 60;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Permiso de micrófono denegado'),
          ),
        );
      }
      return;
    }

    try {
      if (kIsWeb) {
        // En Web: grabar con codificador WAV para generar cabecera RIFF válida
        final webPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: webPath,
        );
      } else {
        // En Móvil/Desktop: grabar en archivo con contenedor MP4/M4A y codec AAC-LC
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _recordedFilePath = path;

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 44100,
            numChannels: 1,
          ),
          path: path,
        );
      }

      setState(() => _isRecording = true);

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _seconds++;
          if (_seconds >= maxDurationSeconds) {
            _finishAndSend();
          }
        });
      });
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Error al iniciar grabación: $e'),
          ),
        );
      }
    }
  }

  Future<void> _finishAndSend() async {
    if (!_isRecording) return;
    _isRecording = false;
    _timer?.cancel();

    try {
      final savedPath = await _recorder.stop();

      if (kIsWeb) {
        if (savedPath != null) {
          final res = await http.get(Uri.parse(savedPath));
          final bytes = res.bodyBytes;
          if (bytes.lengthInBytes > StorageService.maxAudioBytes) {
            throw Exception('El audio supera el límite de 10 MB.');
          }
          if (mounted && bytes.isNotEmpty) {
            widget.onSendAudio(bytes, extension: 'wav', mimeType: 'audio/wav');
            Navigator.of(context).pop();
          }
        }
      } else {
        final path = savedPath ?? _recordedFilePath;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.lengthInBytes > StorageService.maxAudioBytes) {
              throw Exception('El audio supera el límite de 10 MB.');
            }
            if (mounted && bytes.isNotEmpty) {
              widget.onSendAudio(bytes, extension: 'm4a', mimeType: 'audio/mp4');
              Navigator.of(context).pop();
            }
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Error al procesar audio: $e'),
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _isRecording = false;
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      if (!kIsWeb && path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minStr = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secStr = (_seconds % 60).toString().padLeft(2, '0');

    return Dialog(
      backgroundColor: DiscordColors.channelSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _isRecording ? DiscordColors.red.withAlpha(50) : DiscordColors.inputBackground,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.mic,
                  color: _isRecording ? DiscordColors.red : DiscordColors.textSecondary,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _isRecording ? 'Grabando nota de voz...' : 'Iniciando grabadora...',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DiscordColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$minStr:$secStr / 01:00',
              style: const TextStyle(
                fontSize: 22,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: DiscordColors.blurple,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DiscordColors.textSecondary,
                    side: const BorderSide(color: DiscordColors.textSecondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar'),
                  onPressed: _cancelRecording,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DiscordColors.blurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Enviar'),
                  onPressed: !_isRecording ? null : _finishAndSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
