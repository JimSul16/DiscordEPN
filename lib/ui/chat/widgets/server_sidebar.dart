import 'package:flutter/material.dart';
import '../../../core/constants/discord_colors.dart';

class ServerSidebar extends StatelessWidget {
  final VoidCallback onAddChannel;

  const ServerSidebar({
    super.key,
    required this.onAddChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: DiscordColors.serverSidebar,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Icono principal del servidor Discord EPN
          _buildServerIcon(
            context: context,
            label: 'EPN',
            icon: Icons.school,
            isSelected: true,
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(color: DiscordColors.divider, height: 2),
          ),
          const SizedBox(height: 8),
          // Botón para crear canal
          Tooltip(
            message: 'Crear nuevo canal',
            child: InkWell(
              onTap: onAddChannel,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: DiscordColors.inputBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: DiscordColors.green,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerIcon({
    required BuildContext context,
    required String label,
    required IconData icon,
    bool isSelected = false,
  }) {
    return Tooltip(
      message: 'Servidor Discord EPN',
      child: Row(
        children: [
          // Píldora indicadora vertical de selección
          Container(
            width: 4,
            height: isSelected ? 40 : 8,
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: DiscordColors.blurple,
              borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }
}
