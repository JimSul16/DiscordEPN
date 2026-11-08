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
  bool _wasNearBottom = true;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels < 150) {
      final chatProvider = context.read<ChatProvider>();
      if (!chatProvider.loadingMore && chatProvider.hasMore) {
        final before = _scrollController.position.maxScrollExtent;
        chatProvider.loadOlderMessages().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final after = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(
              _scrollController.offset + (after - before),
            );
          });
        });
      }
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final p = _scrollController.position;
    return p.maxScrollExtent - p.pixels < 120;
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

    // Auto-scroll inteligente: solo si el usuario estaba al final o en la carga inicial
    _wasNearBottom = _isNearBottom;
    final grew = messages.length > _lastMessageCount;
    final isInitialLoad = _lastMessageCount == 0 && messages.isNotEmpty;
    _lastMessageCount = messages.length;

    if (grew || isInitialLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (_wasNearBottom || isInitialLoad) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }

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
              Expanded(
                child: Text(
                  activeRoom?.name ?? 'general',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DiscordColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
            if (!chatProvider.hasValidAuthClaim) _buildClaimWarningBanner(chatProvider),
            if (chatProvider.error != null) _buildErrorBanner(chatProvider),
            Expanded(
              child: _buildChatBody(chatProvider),
            ),
            if (typingText != null) _buildTypingBanner(typingText),
            const ChatInputBar(),
          ],
        ),
      );
    }

    // Layout para Escritorio / Web
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
                if (!chatProvider.hasValidAuthClaim) _buildClaimWarningBanner(chatProvider),
                if (chatProvider.error != null) _buildErrorBanner(chatProvider),
                // Feed de mensajes
                Expanded(
                  child: _buildChatBody(chatProvider),
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

  Widget _buildChatBody(ChatProvider chatProvider) {
    if (chatProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: DiscordColors.blurple),
      );
    }

    final messages = chatProvider.messages;
    if (messages.isEmpty) {
      return _buildEmptyChannelView(chatProvider.activeRoom?.name ?? 'general');
    }

    return Column(
      children: [
        if (chatProvider.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: DiscordColors.blurple),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return MessageBubble(message: messages[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClaimWarningBanner(ChatProvider chatProvider) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.security, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Aviso de Seguridad: Tu token de Firebase no tiene el custom claim "role: authenticated". Para que las políticas RLS permitan acceso, configúralo en Firebase Console o Cloud Function.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => chatProvider.refreshAuthToken(),
            child: const Text('Refrescar Token', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ChatProvider chatProvider) {
    return Container(
      width: double.infinity,
      color: DiscordColors.red.withAlpha(200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chatProvider.error ?? 'Error',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () => chatProvider.clearError(),
          ),
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
