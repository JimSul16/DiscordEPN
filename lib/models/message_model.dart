import 'user_profile.dart';
import 'reaction_model.dart';

class MessageModel {
  final String id;
  final String roomId;
  final String senderId;
  final String? content;
  final String type; // 'text', 'image', 'file', 'location', 'audio'
  final String? mediaUrl;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final UserProfile? sender;
  final List<ReactionModel> reactions;

  MessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.content,
    this.type = 'text',
    this.mediaUrl,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.sender,
    this.reactions = const [],
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String?,
      type: json['type'] as String? ?? 'text',
      mediaUrl: json['media_url'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      sender: json['profiles'] != null
          ? UserProfile.fromJson(json['profiles'] as Map<String, dynamic>)
          : null,
      reactions: json['message_reactions'] != null
          ? (json['message_reactions'] as List)
              .map((r) => ReactionModel.fromJson(r as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'type': type,
      'media_url': mediaUrl,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }

  MessageModel copyWith({
    UserProfile? sender,
    List<ReactionModel>? reactions,
  }) {
    return MessageModel(
      id: id,
      roomId: roomId,
      senderId: senderId,
      content: content,
      type: type,
      mediaUrl: mediaUrl,
      latitude: latitude,
      longitude: longitude,
      createdAt: createdAt,
      sender: sender ?? this.sender,
      reactions: reactions ?? this.reactions,
    );
  }
}
