import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/discord_colors.dart';
import '../../core/providers/chat_provider.dart';
import '../chat/widgets/server_sidebar.dart';
import '../chat/widgets/channel_sidebar.dart';
import '../chat/widgets/members_sidebar.dart';
import '../chat/widgets/message_bubble.dart';
import '../chat/widgets/chat_input_bar.dart';
import '../chat/widgets/create_channel_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showMembersOnDesktop = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showCreateChannelDialog() {
    showDialog(
      context: context,
      builder: (_) => const CreateChannelDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final activeRoom = chatProvider.activeRoom;
    final messages = chatProvider.messages;
    final typingText = chatProvider.typingStatusText;

    // Auto-scroll al fondo cuando llegan mensajes nuevos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    if (isMobile) {
      return Scaffold(
        backgroundColor: DiscordColors.chatBackground,
        drawer: Drawer(
          backgroundColor: DiscordColors.channelSidebar,
          child: Row(
            children: [
              ServerSidebar(onAddChannel: _showCreateChannelDialog),
              Expanded(
                child: ChannelSidebar(onAddChannel: _showCreateChannelDialog),
              ),
            ],
          ),
        ),
        endDrawer: const Drawer(
          backgroundColor: DiscordColors.channelSidebar,
          child: SafeArea(child: MembersSidebar()),
        ),
        appBar: AppBar(
          backgroundColor: DiscordColors.chatBackground,
          elevation: 1,
          iconTheme: const IconThemeData(color: DiscordColors.textPrimary),
          title: Row(
            children: [
              const Text(
                '# ',
                style: TextStyle(
                  color: DiscordColors.textSecondary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                activeRoom?.name ?? 'general',
                style: const TextStyle(
                  color: DiscordColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.people_alt, color: DiscordColors.textSecondary),
                tooltip: 'Ver Miembros',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: chatProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: DiscordColors.blurple),
                    )
                  : messages.isEmpty
                      ? _buildEmptyChannelView(activeRoom?.name ?? 'general')
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return MessageBubble(message: messages[index]);
                          },
                        ),
            ),
            if (typingText != null) _buildTypingBanner(typingText),
            const ChatInputBar(),
          ],
        ),
      );
    }

    // Layout de 3 o 4 columnas para Escritorio / Web
    return Scaffold(
      backgroundColor: DiscordColors.chatBackground,
      body: Row(
        children: [
          // 1. Barra de servidores
          ServerSidebar(onAddChannel: _showCreateChannelDialog),
          // 2. Barra de canales
          ChannelSidebar(onAddChannel: _showCreateChannelDialog),
          // 3. Área de Chat Principal
          Expanded(
            child: Column(
              children: [
                // Cabecera superior del canal
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: DiscordColors.chatBackground,
                    border: Border(bottom: BorderSide(color: DiscordColors.serverSidebar, width: 1.5)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '# ',
                        style: TextStyle(
                          color: DiscordColors.textSecondary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        activeRoom?.name ?? 'general',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: DiscordColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '|',
                        style: TextStyle(color: DiscordColors.divider),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Bienvenido al canal oficial de Discord EPN',
                        style: TextStyle(fontSize: 12, color: DiscordColors.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _showMembersOnDesktop ? Icons.people : Icons.people_outline,
                          color: _showMembersOnDesktop ? DiscordColors.textPrimary : DiscordColors.textSecondary,
                        ),
                        tooltip: 'Mostrar/ocultar miembros',
                        onPressed: () {
                          setState(() => _showMembersOnDesktop = !_showMembersOnDesktop);
                        },
                      ),
                    ],
                  ),
                ),
                // Feed de mensajes
                Expanded(
                  child: chatProvider.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: DiscordColors.blurple),
                        )
                      : messages.isEmpty
                          ? _buildEmptyChannelView(activeRoom?.name ?? 'general')
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                return MessageBubble(message: messages[index]);
                              },
                            ),
                ),
                if (typingText != null) _buildTypingBanner(typingText),
                const ChatInputBar(),
              ],
            ),
          ),
          // 4. Barra lateral de miembros (colapsable en Desktop/Web)
          if (_showMembersOnDesktop) const MembersSidebar(),
        ],
      ),
    );
  }

  Widget _buildEmptyChannelView(String channelName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: DiscordColors.inputBackground,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '#',
                style: TextStyle(fontSize: 36, color: DiscordColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '¡Te damos la bienvenida a #$channelName!',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: DiscordColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Este es el inicio del canal #$channelName. ¡Sé el primero en enviar un mensaje!',
            style: const TextStyle(fontSize: 13, color: DiscordColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingBanner(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: DiscordColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: DiscordColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
