import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/discord_colors.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../models/user_profile.dart';

class MembersSidebar extends StatelessWidget {
  const MembersSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final profiles = chatProvider.allProfiles;

    final onlineUsers = profiles.where((p) => p.isOnline).toList();
    final offlineUsers = profiles.where((p) => !p.isOnline).toList();

    return Container(
      width: 220,
      color: DiscordColors.channelSidebar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        children: [
          _buildCategoryHeader('EN LÍNEA — ${onlineUsers.length}'),
          ...onlineUsers.map((u) => _buildMemberTile(u, true)),
          const SizedBox(height: 16),
          _buildCategoryHeader('DESCONECTADOS — ${offlineUsers.length}'),
          ...offlineUsers.map((u) => _buildMemberTile(u, false)),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: DiscordColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMemberTile(UserProfile user, bool isOnline) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: DiscordColors.blurple,
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 14,
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
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: isOnline ? DiscordColors.green : DiscordColors.offline,
                    shape: BoxShape.circle,
                    border: Border.all(color: DiscordColors.channelSidebar, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isOnline ? DiscordColors.textPrimary : DiscordColors.textSecondary,
                  ),
                ),
                if (user.bio.isNotEmpty)
                  Text(
                    user.bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: DiscordColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
