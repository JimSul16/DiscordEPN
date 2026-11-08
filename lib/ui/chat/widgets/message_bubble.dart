import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/discord_colors.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../models/message_model.dart';
import 'image_viewer_dialog.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final currentUserId = chatProvider.currentUserProfile?.id;
    final senderName = message.sender?.displayName ?? 'Usuario';
    final avatarUrl = message.sender?.avatarUrl;
    final timeStr = DateFormat('dd/MM/yyyy HH:mm').format(message.createdAt.toLocal());

    // Agrupar reacciones por emoji
    final Map<String, int> reactionCounts = {};
    final Set<String> userReactions = {};

    for (final r in message.reactions) {
      reactionCounts[r.reaction] = (reactionCounts[r.reaction] ?? 0) + 1;
      if (r.userId == currentUserId) {
        userReactions.add(r.reaction);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar del autor
          CircleAvatar(
            radius: 20,
            backgroundColor: DiscordColors.blurple,
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          // Contenido del mensaje
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera: Nombre y Hora
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: DiscordColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DiscordColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Cuerpo del mensaje según su tipo
                _buildMessageBody(context),
                const SizedBox(height: 6),
                // Fila de reacciones
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...reactionCounts.entries.map((entry) {
                      final emoji = entry.key;
                      final count = entry.value;
                      final isSelected = userReactions.contains(emoji);

                      return InkWell(
                        onTap: () => chatProvider.toggleReaction(message.id, emoji),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? DiscordColors.reactionActive : DiscordColors.reactionBackground,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? DiscordColors.blurple : DiscordColors.reactionBorder,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? DiscordColors.blurple : DiscordColors.textInteractive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    // Botón para añadir reacción
                    InkWell(
                      onTap: () => _showEmojiPicker(context, chatProvider),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: DiscordColors.reactionBackground,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: DiscordColors.reactionBorder, width: 1),
                        ),
                        child: const Icon(
                          Icons.add_reaction_outlined,
                          size: 16,
                          color: DiscordColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBody(BuildContext context) {
    switch (message.type) {
      case 'image':
        return GestureDetector(
          onTap: () {
            if (message.mediaUrl != null) {
              showDialog(
                context: context,
                builder: (_) => ImageViewerDialog(imageUrl: message.mediaUrl!),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: message.mediaUrl != null
                  ? CachedNetworkImage(
                      imageUrl: message.mediaUrl!,
                      placeholder: (context, url) => Container(
                        height: 180,
                        color: DiscordColors.inputBackground,
                        child: const Center(
                          child: CircularProgressIndicator(color: DiscordColors.blurple),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.broken_image,
                        color: DiscordColors.red,
                        size: 48,
                      ),
                    )
                  : const Text('[Foto no disponible]'),
            ),
          ),
        );

      case 'location':
        return Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: DiscordColors.inputBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DiscordColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: DiscordColors.red, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'Ubicación GPS Compartida',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: DiscordColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Latitud: ${message.latitude?.toStringAsFixed(6)}\nLongitud: ${message.longitude?.toStringAsFixed(6)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: DiscordColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DiscordColors.blurple,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Punto en Mapa EPN',
                      style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'audio':
        return _VoicePlayerWidget(
          messageId: message.id,
          audioUrl: message.mediaUrl,
        );

      case 'text':
      default:
        return Text(
          message.content ?? '',
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: DiscordColors.textPrimary,
          ),
        );
    }
  }

  void _showEmojiPicker(BuildContext context, ChatProvider provider) {
    const emojis = ['❤️', '👍', '🔥', '😂', '🎉', '🚀', '👀', '💯'];

    showModalBottomSheet(
      context: context,
      backgroundColor: DiscordColors.channelSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: emojis.map((emoji) {
              return InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  provider.toggleReaction(message.id, emoji);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _VoicePlayerWidget extends StatefulWidget {
  final String messageId;
  final String? audioUrl;

  const _VoicePlayerWidget({
    required this.messageId,
    required this.audioUrl,
  });

  @override
  State<_VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<_VoicePlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _durationSub = _player.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() => _duration = newDuration);
      }
    });

    _positionSub = _player.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() => _position = newPosition);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl == null) return;

    final provider = context.read<ChatProvider>();
    if (_isPlaying) {
      await _player.pause();
      provider.setActiveAudioMessage(null);
    } else {
      provider.setActiveAudioMessage(widget.messageId);
      await _player.play(UrlSource(widget.audioUrl!));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si otro audio comenzó a reproducirse, pausar este inmediatamente
    final activeAudio = context.watch<ChatProvider>().activeAudioMessageId;
    if (activeAudio != widget.messageId && _isPlaying) {
      _player.pause();
    }
    final format = DateFormat('mm:ss');
    final posStr = format.format(DateTime.fromMillisecondsSinceEpoch(_position.inMilliseconds));
    final durStr = format.format(DateTime.fromMillisecondsSinceEpoch(_duration.inMilliseconds));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: DiscordColors.inputBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DiscordColors.divider),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: DiscordColors.blurple,
              size: 32,
            ),
            onPressed: _togglePlay,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0.0,
                  backgroundColor: DiscordColors.divider,
                  valueColor: const AlwaysStoppedAnimation<Color>(DiscordColors.blurple),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      posStr,
                      style: const TextStyle(fontSize: 10, color: DiscordColors.textSecondary),
                    ),
                    Text(
                      durStr,
                      style: const TextStyle(fontSize: 10, color: DiscordColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
