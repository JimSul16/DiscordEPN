import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import '../errors/app_exception.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static const maxAvatarBytes = 5 * 1024 * 1024;
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxAudioBytes = 10 * 1024 * 1024;

  static const Map<String, String> imageMime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  static const Map<String, String> audioMime = {
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'webm': 'audio/webm',
    'ogg': 'audio/ogg',
    'mp3': 'audio/mpeg',
  };

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static void _checkSize(Uint8List bytes, int max, String label) {
    if (bytes.lengthInBytes > max) {
      throw AppException('$label supera el límite de ${max ~/ (1024 * 1024)} MB.');
    }
  }

  // Subir avatar de usuario
  static Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ext = extension.toLowerCase();
    final normalized = ext == 'jpeg' ? 'jpg' : ext;
    final mime = imageMime[normalized];
    if (mime == null) {
      throw const AppException('Formato de imagen para avatar no permitido. Usa JPG, PNG o WebP.');
    }
    _checkSize(bytes, maxAvatarBytes, 'El avatar');

    final ref = _storage.ref().child('avatars/$userId.$normalized');
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: mime),
    );
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  // Subir archivo multimedia al chat
  static Future<String> uploadChatMedia({
    required String roomId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    _checkSize(bytes, maxImageBytes, 'El archivo adjunto');
    final safe = _safeName(fileName);
    final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    final ref = _storage.ref().child('chat_media/$roomId/${id}_$safe');
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: mimeType),
    );
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  // Subir nota de voz / audio
  static Future<String> uploadVoiceNote({
    required String roomId,
    required Uint8List audioBytes,
    String extension = 'm4a',
    String mimeType = 'audio/mp4',
  }) async {
    final ext = extension.toLowerCase();
    final effectiveMime = audioMime[ext] ?? mimeType;
    _checkSize(audioBytes, maxAudioBytes, 'La nota de voz');

    final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    final ref = _storage.ref().child('voice_notes/$roomId/$id.$ext');
    final uploadTask = ref.putData(
      audioBytes,
      SettableMetadata(contentType: effectiveMime),
    );
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }
}
