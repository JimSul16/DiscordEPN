import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../../../core/constants/discord_colors.dart';

class VoiceRecordDialog extends StatefulWidget {
  final Function(Uint8List audioBytes) onSendAudio;

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

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Permiso de micrófono denegado'),
          ),
        );
      }
      return;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.aacLc),
      );

      _streamSub = stream.listen((chunk) {
        _audioChunks.addAll(chunk);
      });

      setState(() => _isRecording = true);

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) {
          setState(() => _seconds++);
        }
      });
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Error al iniciar grabación: $e'),
          ),
        );
      }
    }
  }

  Future<void> _finishAndSend() async {
    _timer?.cancel();
    await _recorder.stop();
    await _streamSub?.cancel();

    if (_audioChunks.isNotEmpty && mounted) {
      final bytes = Uint8List.fromList(_audioChunks);
      widget.onSendAudio(bytes);
      Navigator.of(context).pop();
    }
  }

  Future<void> _cancelRecording() async {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: DiscordColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Grabando Nota de Voz',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: DiscordColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '$minStr:$secStr',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: DiscordColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: _cancelRecording,
                  icon: const Icon(Icons.delete_outline, color: DiscordColors.red),
                  label: const Text('Cancelar', style: TextStyle(color: DiscordColors.red)),
                ),
                ElevatedButton.icon(
                  onPressed: _isRecording ? _finishAndSend : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DiscordColors.blurple,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
