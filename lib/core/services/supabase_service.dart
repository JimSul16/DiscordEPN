import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../../models/room_model.dart';
import '../../models/message_model.dart';
import '../../models/user_profile.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    AppConfig.validate();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      accessToken: () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return null;
        return user.getIdToken();
      },
    );

    // Realtime requiere que se le suministre el token explícitamente al cambiar auth
    FirebaseAuth.instance.idTokenChanges().listen((user) async {
      try {
        final token = await user?.getIdToken();
        await Supabase.instance.client.realtime.setAuth(token);
      } catch (_) {}
    });
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
    } on PostgrestException catch (e) {
      throw AppException(
        e.code == '42501'
            ? 'No tienes permiso para consultar este perfil.'
            : 'Error al consultar perfil (${e.code ?? 'error'}).',
        e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al obtener perfil de usuario.', e);
    }
  }

  static Future<void> upsertProfile(UserProfile profile) async {
    try {
      await client.from('profiles').upsert(profile.toJson());
    } catch (e) {
      throw AppException('Error al actualizar el perfil.', e);
    }
  }

  static Future<void> updatePresence(String userId, bool isOnline) async {
    try {
      await client.from('profiles').update({
        'is_online': isOnline,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
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

  static RealtimeChannel subscribeToProfiles(void Function() onChanged) {
    final channel = client.channel('public:profiles');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => onChanged(),
        )
        .subscribe();
    return channel;
  }

  // --- Salas / Canales ---
  static Future<List<RoomModel>> getRooms() async {
    try {
      final response = await client
          .from('rooms')
          .select()
          .order('created_at', ascending: true);
      return (response as List).map((r) => RoomModel.fromJson(r)).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        e.code == '42501'
            ? 'No tienes permiso para ver los canales.'
            : 'Error al consultar canales (${e.code ?? 'error'}).',
        e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al obtener la lista de canales.', e);
    }
  }

  static Future<RoomModel> createRoom(String name) async {
    final cleanName = name.trim().replaceAll(' ', '-').toLowerCase();
    if (cleanName.isEmpty) {
      throw const AppException('El nombre del canal no puede estar vacío.');
    }

    try {
      final response = await client.rpc(
        'create_room',
        params: {'p_name': cleanName},
      );
      return RoomModel.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const AppException('Ya existe un canal con ese nombre.');
      }
      if (e.code == '22023') {
        throw const AppException(
          'Nombre inválido. Usa 2-32 caracteres: letras minúsculas, números y guiones.',
        );
      }
      // Fallback a inserción directa si el RPC aún no fue migrado en Postgres
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final payload = <String, dynamic>{
        'name': cleanName,
        'is_group': true,
      };
      if (currentUid != null) {
        payload['created_by'] = currentUid;
      }
      final fallbackResponse = await client
          .from('rooms')
          .insert(payload)
          .select()
          .single();
      return RoomModel.fromJson(fallbackResponse);
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al crear el canal: $e', e);
    }
  }

  // --- Mensajes (Paginación: BUG-01 resuelto con descending + reverse) ---
  static Future<List<MessageModel>> getMessages(
    String roomId, {
    int limit = 50,
    DateTime? before,
  }) async {
    try {
      var query = client
          .from('messages')
          .select('*, profiles(*), message_reactions(*)')
          .eq('room_id', roomId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }

      final rows = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        e.code == '42501'
            ? 'No tienes permiso para ver este canal.'
            : 'No se pudo cargar el historial (${e.code ?? 'error'}).',
        e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error de red al cargar el historial.', e);
    }
  }

  static Future<List<MessageModel>> getMessagesBefore({
    required String roomId,
    required DateTime before,
    required String beforeId,
    int limit = 50,
  }) async {
    try {
      final rows = await client
          .from('messages')
          .select('*, profiles(*), message_reactions(*)')
          .eq('room_id', roomId)
          .or('created_at.lt.${before.toUtc().toIso8601String()},'
              'and(created_at.eq.${before.toUtc().toIso8601String()},id.lt.$beforeId)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        e.code == '42501'
            ? 'No tienes permiso para ver este canal.'
            : 'No se pudo cargar mensajes anteriores (${e.code ?? 'error'}).',
        e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error de red al cargar mensajes anteriores.', e);
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
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? senderId;
      await client.from('messages').insert({
        'room_id': roomId,
        'sender_id': currentUid,
        'content': content,
        'type': type,
        'media_url': mediaUrl,
        'latitude': latitude,
        'longitude': longitude,
      });
    } on PostgrestException catch (e) {
      throw AppException(
        e.code == '42501'
            ? 'No tienes permiso para escribir en este canal.'
            : 'Error al enviar el mensaje (${e.code ?? 'error'}).',
        e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al enviar el mensaje: $e', e);
    }
  }

  // --- Suscripción en Tiempo Real para Mensajes con filtros ---
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reads',
          callback: (_) => onDataChanged(),
        )
        .subscribe();

    return channel;
  }

  // --- Reacciones Atómicas ---
  static Future<bool> toggleReaction({
    required String messageId,
    required String reaction,
    String? userId,
  }) async {
    try {
      final res = await client.rpc(
        'toggle_reaction',
        params: {
          'p_message_id': messageId,
          'p_reaction': reaction,
        },
      );
      return res as bool? ?? false;
    } on PostgrestException {
      // Fallback a delete/insert directo
      final currentUid = userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null) throw const AppException('No autenticado');

      final existing = await client
          .from('message_reactions')
          .select()
          .eq('message_id', messageId)
          .eq('user_id', currentUid)
          .eq('reaction', reaction)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', currentUid)
            .eq('reaction', reaction);
        return false;
      } else {
        await client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': currentUid,
          'reaction': reaction,
        });
        return true;
      }
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error al actualizar reacción: $e', e);
    }
  }

  // --- Confirmaciones de Lectura (Read Receipts) ---
  static Future<void> markMessageRead({
    required String messageId,
    required String userId,
    String? roomId,
  }) async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? userId;
      final payload = <String, dynamic>{
        'message_id': messageId,
        'user_id': currentUid,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (roomId != null) payload['room_id'] = roomId;

      await client.from('message_reads').upsert(
        payload,
        onConflict: 'message_id,user_id',
      );
    } catch (_) {}
  }

  // --- Push Tokens ---
  static Future<void> upsertPushToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    try {
      await client.from('user_push_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
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
