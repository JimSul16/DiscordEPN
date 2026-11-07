import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/room_model.dart';
import '../../models/message_model.dart';
import '../../models/user_profile.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
    );
  }

  // --- Perfiles ---
  static Future<UserProfile?> getProfile(String userId) async {
    try {
      final data = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return UserProfile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  static Future<void> upsertProfile(UserProfile profile) async {
    await client.from('profiles').upsert(profile.toJson());
  }

  static Future<void> updatePresence(String userId, bool isOnline) async {
    try {
      await client.from('profiles').update({
        'is_online': isOnline,
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {}
  }

  static Future<List<UserProfile>> getAllProfiles() async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .order('display_name', ascending: true);
      return (response as List).map((p) => UserProfile.fromJson(p)).toList();
    } catch (_) {
      return [];
    }
  }

  // --- Salas / Canales ---
  static Future<List<RoomModel>> getRooms() async {
    try {
      final response = await client
          .from('rooms')
          .select()
          .order('created_at', ascending: true);
      return (response as List).map((r) => RoomModel.fromJson(r)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<RoomModel> createRoom(String name) async {
    final cleanName = name.trim().replaceAll(' ', '-').toLowerCase();
    final response = await client
        .from('rooms')
        .insert({'name': cleanName, 'is_group': true})
        .select()
        .single();
    return RoomModel.fromJson(response);
  }

  // --- Mensajes ---
  static Future<List<MessageModel>> getMessages(String roomId, {int limit = 100}) async {
    try {
      final response = await client
          .from('messages')
          .select('*, profiles(*), message_reactions(*)')
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (response as List).map((m) => MessageModel.fromJson(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> sendMessage({
    required String roomId,
    required String senderId,
    String? content,
    String type = 'text',
    String? mediaUrl,
    double? latitude,
    double? longitude,
  }) async {
    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'type': type,
      'media_url': mediaUrl,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  // --- Suscripción en Tiempo Real para Mensajes ---
  static RealtimeChannel subscribeToRoomMessages({
    required String roomId,
    required void Function() onDataChanged,
  }) {
    final channel = client.channel('public:room:$roomId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => onDataChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => onDataChanged(),
        )
        .subscribe();

    return channel;
  }

  // --- Reacciones ---
  static Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String reaction,
  }) async {
    try {
      final existing = await client
          .from('message_reactions')
          .select()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('reaction', reaction)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', userId)
            .eq('reaction', reaction);
      } else {
        await client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': userId,
          'reaction': reaction,
        });
      }
    } catch (_) {}
  }

  // --- Confirmaciones de Lectura (Read Receipts) ---
  static Future<void> markMessageRead({
    required String messageId,
    required String userId,
  }) async {
    try {
      await client.from('message_reads').upsert({
        'message_id': messageId,
        'user_id': userId,
        'read_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // --- Indicador de "Escribiendo..." (Typing Indicator) ---
  static RealtimeChannel listenTypingStatus({
    required String roomId,
    required void Function(String userName, bool isTyping) onTyping,
  }) {
    final channel = client.channel('typing:$roomId');

    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final userName = payload['user_name'] as String? ?? 'Alguien';
        final isTyping = payload['is_typing'] as bool? ?? false;
        onTyping(userName, isTyping);
      },
    ).subscribe();

    return channel;
  }

  static Future<void> broadcastTyping({
    required RealtimeChannel channel,
    required String userName,
    required bool isTyping,
  }) async {
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_name': userName,
          'is_typing': isTyping,
        },
      );
    } catch (_) {}
  }
}
