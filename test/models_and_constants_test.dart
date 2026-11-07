import 'package:flutter_test/flutter_test.dart';
import 'package:discord_epn/core/constants/discord_colors.dart';
import 'package:discord_epn/models/user_profile.dart';
import 'package:discord_epn/models/room_model.dart';
import 'package:discord_epn/models/message_model.dart';
import 'package:discord_epn/models/reaction_model.dart';

void main() {
  group('DiscordColors Constants', () {
    test('Paleta oficial de Discord está correctamente definida', () {
      expect(DiscordColors.blurple.toARGB32(), equals(0xFF5865F2));
      expect(DiscordColors.chatBackground.toARGB32(), equals(0xFF313338));
      expect(DiscordColors.channelSidebar.toARGB32(), equals(0xFF2B2D31));
      expect(DiscordColors.serverSidebar.toARGB32(), equals(0xFF1E1F22));
      expect(DiscordColors.green.toARGB32(), equals(0xFF23A55A));
      expect(DiscordColors.red.toARGB32(), equals(0xFFF23F43));
    });
  });

  group('UserProfile Model', () {
    test('Serialización y deserialización correcta de UserProfile', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'usr-123',
        displayName: 'Estudiante EPN',
        avatarUrl: 'https://cdn.discordepn.app/avatar.png',
        bio: 'Desarrollando apps móviles',
        isOnline: true,
        lastSeen: now,
      );

      final json = profile.toJson();
      expect(json['id'], equals('usr-123'));
      expect(json['display_name'], equals('Estudiante EPN'));
      expect(json['avatar_url'], equals('https://cdn.discordepn.app/avatar.png'));
      expect(json['bio'], equals('Desarrollando apps móviles'));
      expect(json['is_online'], isTrue);

      final parsed = UserProfile.fromJson(json);
      expect(parsed.id, equals('usr-123'));
      expect(parsed.displayName, equals('Estudiante EPN'));
      expect(parsed.isOnline, isTrue);
    });

    test('copyWith preserva y modifica campos esperados', () {
      final profile = UserProfile(
        id: 'usr-1',
        displayName: 'Original',
        lastSeen: DateTime.now(),
      );

      final updated = profile.copyWith(displayName: 'Modificado', isOnline: true);
      expect(updated.id, equals('usr-1'));
      expect(updated.displayName, equals('Modificado'));
      expect(updated.isOnline, isTrue);
    });
  });

  group('RoomModel Model', () {
    test('Serialización y deserialización correcta de RoomModel', () {
      final now = DateTime.now();
      final room = RoomModel(
        id: 'room-abc',
        name: 'multimedia',
        isGroup: true,
        createdAt: now,
      );

      final json = room.toJson();
      expect(json['id'], equals('room-abc'));
      expect(json['name'], equals('multimedia'));
      expect(json['is_group'], isTrue);

      final parsed = RoomModel.fromJson(json);
      expect(parsed.id, equals('room-abc'));
      expect(parsed.name, equals('multimedia'));
    });
  });

  group('ReactionModel Model', () {
    test('Serialización y deserialización correcta de ReactionModel', () {
      final reaction = ReactionModel(
        messageId: 'msg-1',
        userId: 'usr-1',
        reaction: '🔥',
      );

      final json = reaction.toJson();
      expect(json['message_id'], equals('msg-1'));
      expect(json['user_id'], equals('usr-1'));
      expect(json['reaction'], equals('🔥'));

      final parsed = ReactionModel.fromJson(json);
      expect(parsed.messageId, equals('msg-1'));
      expect(parsed.userId, equals('usr-1'));
      expect(parsed.reaction, equals('🔥'));
    });
  });

  group('MessageModel Model', () {
    test('Serialización y deserialización polimórfica de MessageModel', () {
      final now = DateTime.now();
      final msg = MessageModel(
        id: 'msg-999',
        roomId: 'room-general',
        senderId: 'usr-456',
        content: 'Ubicación de la facultad',
        type: 'location',
        latitude: -0.2105,
        longitude: -78.4891,
        createdAt: now,
      );

      final json = msg.toJson();
      expect(json['id'], equals('msg-999'));
      expect(json['room_id'], equals('room-general'));
      expect(json['sender_id'], equals('usr-456'));
      expect(json['type'], equals('location'));
      expect(json['latitude'], equals(-0.2105));
      expect(json['longitude'], equals(-78.4891));

      final parsed = MessageModel.fromJson(json);
      expect(parsed.id, equals('msg-999'));
      expect(parsed.type, equals('location'));
      expect(parsed.latitude, equals(-0.2105));
    });
  });
}
