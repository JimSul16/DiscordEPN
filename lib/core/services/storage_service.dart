import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // Subir avatar de usuario
  static Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ref = _storage.ref().child('avatars/$userId.$extension');
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/$extension'),
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child('chat_media/$roomId/${timestamp}_$fileName');
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
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child('voice_notes/$roomId/$timestamp.m4a');
    final uploadTask = ref.putData(
      audioBytes,
      SettableMetadata(contentType: 'audio/m4a'),
    );
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }
}
