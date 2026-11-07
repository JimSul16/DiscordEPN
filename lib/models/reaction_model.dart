class ReactionModel {
  final String messageId;
  final String userId;
  final String reaction;

  ReactionModel({
    required this.messageId,
    required this.userId,
    required this.reaction,
  });

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      messageId: json['message_id'] as String,
      userId: json['user_id'] as String,
      reaction: json['reaction'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'user_id': userId,
      'reaction': reaction,
    };
  }
}
