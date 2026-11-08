import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/discord_colors.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/services/storage_service.dart';

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

  Uint8List? _pendingAvatar;
  String? _pendingAvatarExt;

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

  Future<void> _pickAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    final ext = image.name.split('.').last.toLowerCase();
    if (!StorageService.imageMime.containsKey(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('Formato no permitido. Usa JPG, PNG o WebP.'),
          ),
        );
      }
      return;
    }

    final bytes = await image.readAsBytes();
    if (bytes.lengthInBytes > StorageService.maxAvatarBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DiscordColors.red,
            content: Text('El avatar no puede superar 5 MB.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingAvatar = bytes;
      _pendingAvatarExt = ext;
    });
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();

    if (name.length < 3 || name.length > 32) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('El nombre de usuario debe tener entre 3 y 32 caracteres.'),
        ),
      );
      return;
    }

    if (bio.length > 190) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('La biografía no puede superar los 190 caracteres.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isSaving = true);
    try {
      await context.read<ChatProvider>().updateProfile(
        displayName: name,
        bio: bio,
        newAvatarBytes: _pendingAvatar,
        avatarExtension: _pendingAvatarExt,
      );

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: DiscordColors.green,
          content: Text('Perfil actualizado con éxito'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: DiscordColors.red,
          content: Text('Error al guardar perfil: $e'),
        ),
      );
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: DiscordColors.channelSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
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
                      backgroundImage: _pendingAvatar != null
                          ? MemoryImage(_pendingAvatar!)
                          : (profile?.avatarUrl != null
                              ? CachedNetworkImageProvider(profile!.avatarUrl!) as ImageProvider
                              : null),
                      child: (_pendingAvatar == null && profile?.avatarUrl == null)
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
                          onTap: _isSaving ? null : _pickAvatar,
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
                maxLength: 32,
                style: const TextStyle(color: DiscordColors.textPrimary),
                decoration: InputDecoration(
                  counterText: '',
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
                maxLength: 190,
                maxLines: 2,
                style: const TextStyle(color: DiscordColors.textPrimary),
                decoration: InputDecoration(
                  counterText: '',
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
