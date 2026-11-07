import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/discord_colors.dart';
import '../../core/providers/chat_provider.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final profile = context.read<ChatProvider>().currentUserProfile;
    if (profile != null) {
      _nameController.text = profile.displayName;
      _bioController.text = profile.bio;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() => _isSaving = true);
    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();

      if (mounted) {
        await context.read<ChatProvider>().updateProfile(
          newAvatarBytes: bytes,
          avatarExtension: ext.isNotEmpty ? ext : 'jpg',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Error al subir avatar: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await context.read<ChatProvider>().updateProfile(
        displayName: _nameController.text.trim(),
        bio: _bioController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DiscordColors.green,
            content: Text('Perfil actualizado con éxito'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Error al guardar perfil: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final profile = chatProvider.currentUserProfile;

    return Dialog(
      backgroundColor: DiscordColors.channelSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Perfil de Usuario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: DiscordColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: DiscordColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: DiscordColors.divider),
              const SizedBox(height: 12),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: DiscordColors.blurple,
                      backgroundImage: profile?.avatarUrl != null
                          ? CachedNetworkImageProvider(profile!.avatarUrl!)
                          : null,
                      child: profile?.avatarUrl == null
                          ? Text(
                              profile?.displayName.isNotEmpty == true
                                  ? profile!.displayName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Material(
                        color: DiscordColors.inputBackground,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _isSaving ? null : _pickAndUploadAvatar,
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.camera_alt,
                              size: 18,
                              color: DiscordColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'NOMBRE PARA MOSTRAR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: DiscordColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: DiscordColors.textPrimary),
                decoration: InputDecoration(
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
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SOBRE MÍ (ESTADO)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: DiscordColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bioController,
                maxLines: 2,
                style: const TextStyle(color: DiscordColors.textPrimary),
                decoration: InputDecoration(
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
                  hintText: '¡Hola! Estoy usando Discord EPN.',
                  hintStyle: TextStyle(color: DiscordColors.textSecondary.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await chatProvider.signOut();
                    },
                    icon: const Icon(Icons.logout, color: DiscordColors.red, size: 18),
                    label: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: DiscordColors.red),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DiscordColors.blurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Guardar cambios'),
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
