import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/room_model.dart';
import '../../models/message_model.dart';
import '../../models/user_profile.dart';
import '../errors/app_exception.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

class ChatProvider extends ChangeNotifier {
  UserProfile? _currentUserProfile;
  List<RoomModel> _rooms = [];
  RoomModel? _activeRoom;
  List<MessageModel> _messages = [];
  List<UserProfile> _allProfiles = [];
  bool _isLoading = false;
  String? _error;
  String? _typingStatusText;

  // Control de paginación e historial
  bool _hasMore = true;
  bool _loadingMore = false;

  // Prevención de condición de carrera (BUG-02)
  int _roomRequest = 0;
  Timer? _reloadDebounce;

  // Suscripciones en tiempo real
  RealtimeChannel? _messagesSubscription;
  RealtimeChannel? _typingSubscription;
  RealtimeChannel? _profilesSubscription;
  Timer? _typingTimer;

  // Coordinador de reproducción de audio único (BUG-14)
  String? _activeAudioMessageId;

  // Heartbeat de presencia (BUG-05)
  Timer? _presenceHeartbeat;

  UserProfile? get currentUserProfile => _currentUserProfile;
  List<RoomModel> get rooms => _rooms;
  RoomModel? get activeRoom => _activeRoom;
  List<MessageModel> get messages => _messages;
  List<UserProfile> get allProfiles => _allProfiles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get typingStatusText => _typingStatusText;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  String? get activeAudioMessageId => _activeAudioMessageId;

  void setActiveAudioMessage(String? messageId) {
    if (_activeAudioMessageId != messageId) {
      _activeAudioMessageId = messageId;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> initializeUser(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUserProfile = await SupabaseService.getProfile(userId);
      if (_currentUserProfile == null) {
        // Fallback resiliente si el perfil aún no se registró en Supabase
        final firebaseUser = AuthService.currentUser;
        final newProfile = UserProfile(
          id: userId,
          displayName: firebaseUser?.displayName ?? (firebaseUser?.email?.split('@').first ?? 'Usuario'),
          bio: '¡Hola! Estoy usando Discord EPN.',
          isOnline: true,
          lastSeen: DateTime.now(),
        );
        await SupabaseService.upsertProfile(newProfile);
        _currentUserProfile = newProfile;
      }

      await loadRooms();
      await loadProfiles();

      // Suscribirse a cambios de perfiles en tiempo real
      _profilesSubscription?.unsubscribe();
      _profilesSubscription = SupabaseService.subscribeToProfiles(() {
        loadProfiles();
      });

      // Iniciar heartbeat de presencia
      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
        if (_currentUserProfile != null) {
          SupabaseService.updatePresence(_currentUserProfile!.id, true);
        }
      });

      if (_rooms.isNotEmpty && _activeRoom == null) {
        await selectRoom(_rooms.first);
      }
    } on AppException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'No se pudo inicializar el chat: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRooms() async {
    try {
      _rooms = await SupabaseService.getRooms();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadProfiles() async {
    try {
      _allProfiles = await SupabaseService.getAllProfiles();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectRoom(RoomModel room) async {
    if (_activeRoom?.id == room.id && _messages.isNotEmpty) return;

    final request = ++_roomRequest;

    _activeRoom = room;
    _messages = [];
    _typingStatusText = null;
    _isLoading = true;
    _error = null;
    _hasMore = true;
    notifyListeners();

    _cleanupSubscriptions();

    try {
      final loaded = await SupabaseService.getMessages(room.id, limit: 50);
      if (request != _roomRequest || _activeRoom?.id != room.id) return;

      _messages = loaded;
      _hasMore = loaded.length >= 50;

      // Suscribirse a mensajes en tiempo real con debounce
      _messagesSubscription = SupabaseService.subscribeToRoomMessages(
        roomId: room.id,
        onDataChanged: () => _scheduleReload(room.id, request),
      );

      // Suscribirse al indicador de escritura
      _typingSubscription = SupabaseService.listenTypingStatus(
        roomId: room.id,
        onTyping: (userName, isTyping) {
          if (request != _roomRequest || _activeRoom?.id != room.id) return;
          if (_currentUserProfile?.displayName == userName) return;

          if (isTyping) {
            _typingStatusText = '$userName está escribiendo...';
            notifyListeners();

            _typingTimer?.cancel();
            _typingTimer = Timer(const Duration(seconds: 3), () {
              if (request == _roomRequest) {
                _typingStatusText = null;
                notifyListeners();
              }
            });
          } else {
            _typingStatusText = null;
            notifyListeners();
          }
        },
      );
    } on AppException catch (e) {
      if (request == _roomRequest) _error = e.message;
    } catch (e) {
      if (request == _roomRequest) _error = 'Error al cargar mensajes del canal.';
    } finally {
      if (request == _roomRequest) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _scheduleReload(String roomId, int request) {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 150), () async {
      if (request != _roomRequest || _activeRoom?.id != roomId) return;
      try {
        final loaded = await SupabaseService.getMessages(roomId, limit: 50);
        if (request != _roomRequest || _activeRoom?.id != roomId) return;
        _messages = loaded;
        _error = null;
        notifyListeners();
      } catch (_) {}
    });
  }

  Future<void> loadOlderMessages() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty || _activeRoom == null) {
      return;
    }
    _loadingMore = true;
    notifyListeners();

    final first = _messages.first;
    try {
      final older = await SupabaseService.getMessagesBefore(
        roomId: _activeRoom!.id,
        before: first.createdAt,
        beforeId: first.id,
        limit: 50,
      );
      _hasMore = older.length >= 50;
      _messages = [...older, ..._messages];
    } catch (_) {
      // Evitar bloquear si falla paginación
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void notifyTyping(bool isTyping) {
    if (_typingSubscription != null && _currentUserProfile != null) {
      SupabaseService.broadcastTyping(
        channel: _typingSubscription!,
        userName: _currentUserProfile!.displayName,
        isTyping: isTyping,
      );
    }
  }

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty || _activeRoom == null || _currentUserProfile == null) return;

    await SupabaseService.sendMessage(
      roomId: _activeRoom!.id,
      senderId: _currentUserProfile!.id,
      content: text.trim(),
      type: 'text',
    );
  }

  Future<void> sendImageMessage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (_activeRoom == null || _currentUserProfile == null) return;

    final mediaUrl = await StorageService.uploadChatMedia(
      roomId: _activeRoom!.id,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );

    await SupabaseService.sendMessage(
      roomId: _activeRoom!.id,
      senderId: _currentUserProfile!.id,
      content: 'Foto adjunta',
      type: 'image',
      mediaUrl: mediaUrl,
    );
  }

  Future<void> sendLocationMessage({
    required double latitude,
    required double longitude,
  }) async {
    if (_activeRoom == null || _currentUserProfile == null) return;

    await SupabaseService.sendMessage(
      roomId: _activeRoom!.id,
      senderId: _currentUserProfile!.id,
      content: '📍 Ubicación compartida',
      type: 'location',
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> sendVoiceNote({
    required Uint8List audioBytes,
    String extension = 'm4a',
    String mimeType = 'audio/mp4',
  }) async {
    if (_activeRoom == null || _currentUserProfile == null) return;

    final mediaUrl = await StorageService.uploadVoiceNote(
      roomId: _activeRoom!.id,
      audioBytes: audioBytes,
      extension: extension,
      mimeType: mimeType,
    );

    await SupabaseService.sendMessage(
      roomId: _activeRoom!.id,
      senderId: _currentUserProfile!.id,
      content: '🎙️ Nota de voz',
      type: 'audio',
      mediaUrl: mediaUrl,
    );
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    if (_currentUserProfile == null || _activeRoom == null) return;

    try {
      await SupabaseService.toggleReaction(
        messageId: messageId,
        reaction: emoji,
        userId: _currentUserProfile!.id,
      );

      _scheduleReload(_activeRoom!.id, _roomRequest);
    } on AppException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> createRoom(String name) async {
    try {
      final newRoom = await SupabaseService.createRoom(name);
      if (!_rooms.any((r) => r.id == newRoom.id)) {
        _rooms.add(newRoom);
      }
      await selectRoom(newRoom);
      notifyListeners();
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al crear el canal: $e', e);
    }
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    Uint8List? newAvatarBytes,
    String? avatarExtension,
  }) async {
    if (_currentUserProfile == null) return;

    String? avatarUrl = _currentUserProfile!.avatarUrl;
    if (newAvatarBytes != null && avatarExtension != null) {
      avatarUrl = await StorageService.uploadAvatar(
        userId: _currentUserProfile!.id,
        bytes: newAvatarBytes,
        extension: avatarExtension,
      );
    }

    final updated = _currentUserProfile!.copyWith(
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl,
    );

    await SupabaseService.upsertProfile(updated);
    _currentUserProfile = updated;
    await loadProfiles();
    notifyListeners();
  }

  Future<void> signOut() async {
    _cleanupSubscriptions();
    _presenceHeartbeat?.cancel();
    _currentUserProfile = null;
    _activeRoom = null;
    _messages = [];
    _rooms = [];
    await AuthService.signOut();
    notifyListeners();
  }

  void _cleanupSubscriptions() {
    _reloadDebounce?.cancel();
    _typingTimer?.cancel();
    if (_messagesSubscription != null) {
      SupabaseService.client.removeChannel(_messagesSubscription!);
      _messagesSubscription = null;
    }
    if (_typingSubscription != null) {
      SupabaseService.client.removeChannel(_typingSubscription!);
      _typingSubscription = null;
    }
  }

  @override
  void dispose() {
    _presenceHeartbeat?.cancel();
    _cleanupSubscriptions();
    if (_profilesSubscription != null) {
      SupabaseService.client.removeChannel(_profilesSubscription!);
    }
    super.dispose();
  }
}
