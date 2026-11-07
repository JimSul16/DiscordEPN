class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String bio;
  final bool isOnline;
  final DateTime lastSeen;

  UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio = '¡Hola! Estoy usando Discord EPN.',
    this.isOnline = false,
    required this.lastSeen,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Usuario',
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String? ?? '¡Hola! Estoy usando Discord EPN.',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'is_online': isOnline,
      'last_seen': lastSeen.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
