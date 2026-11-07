class RoomModel {
  final String id;
  final String name;
  final bool isGroup;
  final String? avatarUrl;
  final DateTime createdAt;

  RoomModel({
    required this.id,
    required this.name,
    this.isGroup = true,
    this.avatarUrl,
    required this.createdAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'general',
      isGroup: json['is_group'] as bool? ?? true,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_group': isGroup,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
