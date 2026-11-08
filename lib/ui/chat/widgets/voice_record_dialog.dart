import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
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
  final List<int> _audioChunks = [];
  StreamSubscription<Uint8List>? _streamSub;
  Timer? _timer;
  int _seconds = 0;
  bool _isRecording = false;

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
      // Usar aacLc en móvil y wav/pcm en web según compatibilidad
      final encoder = kIsWeb ? AudioEncoder.pcm16bits : AudioEncoder.aacLc;
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: encoder,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );

      _streamSub = stream.listen((chunk) {
        if (_audioChunks.length + chunk.length > StorageService.maxAudioBytes) {
          _finishAndSend();
          return;
        }
        _audioChunks.addAll(chunk);
      });

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
    await _recorder.stop();
    await _streamSub?.cancel();

    if (_audioChunks.isNotEmpty && mounted) {
      final bytes = Uint8List.fromList(_audioChunks);
      final ext = kIsWeb ? 'wav' : 'm4a';
      final mime = kIsWeb ? 'audio/wav' : 'audio/mp4';
      widget.onSendAudio(bytes, extension: ext, mimeType: mime);
      Navigator.of(context).pop();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cancelRecording() async {
    _isRecording = false;
    _timer?.cancel();
    await _recorder.cancel();
    await _streamSub?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _streamSub?.cancel();
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
              _isRecording ? 'Grabando mensaje de voz...' : 'Iniciando grabadora...',
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
                  onPressed: _audioChunks.isEmpty ? null : _finishAndSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
