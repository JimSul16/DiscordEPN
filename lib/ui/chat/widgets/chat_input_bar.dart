import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/discord_colors.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/services/storage_service.dart';
import 'voice_record_dialog.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isSending = false;

  Timer? _typingStop;
  bool _typingSent = false;

  @override
  void dispose() {
    _typingStop?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    final provider = context.read<ChatProvider>();
    if (value.trim().isEmpty) {
      _typingStop?.cancel();
      if (_typingSent) {
        _typingSent = false;
        provider.notifyTyping(false);
      }
      return;
    }

    if (!_typingSent) {
      _typingSent = true;
      provider.notifyTyping(true);
    }

    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), () {
      _typingSent = false;
      provider.notifyTyping(false);
    });
  }

  Future<void> _handleSendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    if (text.length > 4000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('El mensaje no puede superar los 4000 caracteres.'),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    _typingStop?.cancel();
    _typingSent = false;
    context.read<ChatProvider>().notifyTyping(false);

    try {
      await context.read<ChatProvider>().sendTextMessage(text);
      if (!mounted) return;
      // Limpiar solo cuando el envío fue exitoso (BUG-22 resuelto)
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: DiscordColors.red, content: Text('Error al enviar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _isSending = true);
    try {
      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > StorageService.maxImageBytes) {
        throw Exception('La imagen supera el límite permitido de 10 MB.');
      }

      final name = image.name;
      final ext = name.split('.').last.toLowerCase();
      final normalized = ext == 'jpeg' ? 'jpg' : ext;
      final mime = StorageService.imageMime[normalized];
      if (mime == null) {
        throw Exception('Formato no permitido: .$ext. Solo se aceptan JPG, PNG, WebP o GIF.');
      }

      if (mounted) {
        await context.read<ChatProvider>().sendImageMessage(
          bytes: bytes,
          fileName: name,
          mimeType: mime,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: DiscordColors.red, content: Text('Error al subir imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _shareLocation() async {
    setState(() => _isSending = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('El servicio de ubicación GPS está desactivado');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permisos de ubicación denegados');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permisos de ubicación denegados permanentemente');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        await context.read<ChatProvider>().sendLocationMessage(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: DiscordColors.red, content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _openVoiceRecorder() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoiceRecordDialog(
        onSendAudio: (audioBytes, {String extension = 'm4a', String mimeType = 'audio/mp4'}) async {
          setState(() => _isSending = true);
          try {
            await context.read<ChatProvider>().sendVoiceNote(
              audioBytes: audioBytes,
              extension: extension,
              mimeType: mimeType,
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: DiscordColors.red, content: Text('Error al enviar audio: $e')),
              );
            }
          } finally {
            if (mounted) setState(() => _isSending = false);
          }
        },
      ),
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DiscordColors.channelSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library, color: DiscordColors.blurple),
                  title: const Text('Subir Imagen (Firebase Storage)', style: TextStyle(color: DiscordColors.textPrimary)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAndSendImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on, color: DiscordColors.green),
                  title: const Text('Compartir Ubicación GPS', style: TextStyle(color: DiscordColors.textPrimary)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _shareLocation();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: DiscordColors.red),
                  title: const Text('Grabar Nota de Voz', style: TextStyle(color: DiscordColors.textPrimary)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openVoiceRecorder();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeRoom = context.watch<ChatProvider>().activeRoom;
    final channelName = activeRoom?.name ?? 'general';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: DiscordColors.inputBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Botón "+" para adjuntos
            IconButton(
              icon: const Icon(Icons.add_circle, color: DiscordColors.textSecondary, size: 24),
              tooltip: 'Adjuntar archivos o ubicación',
              onPressed: _isSending ? null : _showAttachmentMenu,
            ),
            // Campo de texto
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: DiscordColors.textPrimary, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Enviar mensaje a #$channelName',
                  hintStyle: TextStyle(
                    color: DiscordColors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _handleSendText(),
              ),
            ),
            // Botón de nota de voz directa
            IconButton(
              icon: const Icon(Icons.mic, color: DiscordColors.textSecondary, size: 22),
              tooltip: 'Grabar audio',
              onPressed: _isSending ? null : _openVoiceRecorder,
            ),
            // Botón Enviar
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: DiscordColors.blurple),
                    )
                  : const Icon(Icons.send, color: DiscordColors.blurple, size: 22),
              tooltip: 'Enviar mensaje',
              onPressed: _isSending ? null : _handleSendText,
            ),
          ],
        ),
      ),
    );
  }
}
