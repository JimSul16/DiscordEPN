import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/discord_colors.dart';
import '../../../core/providers/chat_provider.dart';

class CreateChannelDialog extends StatefulWidget {
  const CreateChannelDialog({super.key});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('El nombre del canal no puede estar vacío.'),
        ),
      );
      return;
    }

    final clean = raw.replaceAll(' ', '-').toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,31}$').hasMatch(clean)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('Usa de 2 a 32 caracteres (solo minúsculas, números y guiones).'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);
    try {
      await context.read<ChatProvider>().createRoom(clean);
      if (mounted) {
        navigator.pop();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('$e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DiscordColors.channelSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Crear canal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: DiscordColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'En los canales de texto es donde se reúne y conversa la comunidad.',
                style: TextStyle(fontSize: 13, color: DiscordColors.textSecondary),
              ),
              const SizedBox(height: 20),
              const Text(
                'NOMBRE DEL CANAL *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: DiscordColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: DiscordColors.textPrimary),
                decoration: InputDecoration(
                  prefixText: '# ',
                  prefixStyle: const TextStyle(
                    color: DiscordColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  filled: true,
                  fillColor: DiscordColors.serverSidebar,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: DiscordColors.blurple, width: 2),
                  ),
                  hintText: 'nuevo-canal',
                  hintStyle: TextStyle(color: DiscordColors.textSecondary.withValues(alpha: 0.5)),
                ),
                onSubmitted: (_) => _handleCreate(),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar', style: TextStyle(color: DiscordColors.textPrimary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DiscordColors.blurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Crear canal'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
