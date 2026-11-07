import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/room_model.dart';
import '../../models/message_model.dart';
import '../../models/user_profile.dart';
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
  String? _typingStatusText;

  RealtimeChannel? _messagesSubscription;
  RealtimeChannel? _typingSubscription;
  Timer? _typingTimer;

  UserProfile? get currentUserProfile => _currentUserProfile;
  List<RoomModel> get rooms => _rooms;
  RoomModel? get activeRoom => _activeRoom;
  List<MessageModel> get messages => _messages;
  List<UserProfile> get allProfiles => _allProfiles;
  bool get isLoading => _isLoading;
  String? get typingStatusText => _typingStatusText;

  Future<void> initializeUser(String userId) async {
    _isLoading = true;
    notifyListeners();

    _currentUserProfile = await SupabaseService.getProfile(userId);
    await loadRooms();
    await loadProfiles();

    if (_rooms.isNotEmpty && _activeRoom == null) {
      await selectRoom(_rooms.first);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadRooms() async {
    _rooms = await SupabaseService.getRooms();
    notifyListeners();
  }

  Future<void> loadProfiles() async {
    _allProfiles = await SupabaseService.getAllProfiles();
    notifyListeners();
  }

  Future<void> selectRoom(RoomModel room) async {
    if (_activeRoom?.id == room.id) return;

    _activeRoom = room;
    _messages = [];
    _typingStatusText = null;
    notifyListeners();

    _cleanupSubscriptions();

    // Cargar mensajes iniciales
    _messages = await SupabaseService.getMessages(room.id);
    notifyListeners();

    // Suscribir a mensajes en tiempo real
    _messagesSubscription = SupabaseService.subscribeToRoomMessages(
      roomId: room.id,
      onDataChanged: () async {
        final updated = await SupabaseService.getMessages(room.id);
        _messages = updated;
        notifyListeners();
      },
    );

    // Suscribir a indicador de escritura
    _typingSubscription = SupabaseService.listenTypingStatus(
      roomId: room.id,
      onTyping: (userName, isTyping) {
        if (_currentUserProfile?.displayName == userName) return;

        if (isTyping) {
          _typingStatusText = '$userName está escribiendo...';
          notifyListeners();

          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 3), () {
            _typingStatusText = null;
            notifyListeners();
          });
        } else {
          _typingStatusText = null;
          notifyListeners();
        }
      },
    );
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
  }) async {
    if (_activeRoom == null || _currentUserProfile == null) return;

    final mediaUrl = await StorageService.uploadVoiceNote(
      roomId: _activeRoom!.id,
      audioBytes: audioBytes,
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
    if (_currentUserProfile == null) return;

    await SupabaseService.toggleReaction(
      messageId: messageId,
      userId: _currentUserProfile!.id,
      reaction: emoji,
    );

    if (_activeRoom != null) {
      _messages = await SupabaseService.getMessages(_activeRoom!.id);
      notifyListeners();
    }
  }

  Future<void> createRoom(String name) async {
    final newRoom = await SupabaseService.createRoom(name);
    _rooms.add(newRoom);
    await selectRoom(newRoom);
    notifyListeners();
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
    _currentUserProfile = null;
    _activeRoom = null;
    _messages = [];
    _rooms = [];
    await AuthService.signOut();
    notifyListeners();
  }

  void _cleanupSubscriptions() {
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
    _cleanupSubscriptions();
    super.dispose();
  }
}
