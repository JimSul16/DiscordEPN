import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/discord_colors.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../models/room_model.dart';
import '../../profile/profile_dialog.dart';

class ChannelSidebar extends StatelessWidget {
  final VoidCallback onAddChannel;

  const ChannelSidebar({
    super.key,
    required this.onAddChannel,
  });

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final activeRoom = chatProvider.activeRoom;
    final currentUser = chatProvider.currentUserProfile;

    return Container(
      width: 240,
      color: DiscordColors.channelSidebar,
      child: Column(
        children: [
          // Header del Servidor
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DiscordColors.serverSidebar, width: 1.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Discord EPN',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: DiscordColors.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: DiscordColors.textSecondary, size: 20),
                  tooltip: 'Crear canal',
                  onPressed: onAddChannel,
                ),
              ],
            ),
          ),
          // Sección de Canales de Texto
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CANALES DE TEXTO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: DiscordColors.textSecondary,
                  ),
                ),
                InkWell(
                  onTap: onAddChannel,
                  child: const Icon(Icons.add, size: 16, color: DiscordColors.textSecondary),
                ),
              ],
            ),
          ),
          // Lista de Canales
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: chatProvider.rooms.length,
              itemBuilder: (context, index) {
                final room = chatProvider.rooms[index];
                final isSelected = activeRoom?.id == room.id;

                return _buildChannelItem(
                  context: context,
                  room: room,
                  isSelected: isSelected,
                  onTap: () {
                    chatProvider.selectRoom(room);
                    // Si estamos en móvil, cerramos el drawer si está abierto
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
          // Dock de Usuario en la esquina inferior
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: DiscordColors.serverSidebar,
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: DiscordColors.blurple,
                      backgroundImage: currentUser?.avatarUrl != null
                          ? CachedNetworkImageProvider(currentUser!.avatarUrl!)
                          : null,
                      child: currentUser?.avatarUrl == null
                          ? Text(
                              currentUser?.displayName.isNotEmpty == true
                                  ? currentUser!.displayName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: DiscordColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: DiscordColors.serverSidebar, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser?.displayName ?? 'Cargando...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: DiscordColors.textPrimary,
                        ),
                      ),
                      const Text(
                        'En línea',
                        style: TextStyle(
                          fontSize: 11,
                          color: DiscordColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: DiscordColors.textSecondary, size: 20),
                  tooltip: 'Ajustes de Perfil',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ProfileDialog(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelItem({
    required BuildContext context,
    required RoomModel room,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? DiscordColors.inputBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: const Text(
          '#',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: DiscordColors.textSecondary,
          ),
        ),
        title: Text(
          room.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? DiscordColors.textPrimary : DiscordColors.textSecondary,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
