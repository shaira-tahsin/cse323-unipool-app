import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Stream of messages for a chat, ordered oldest → newest ──────────────
  Stream<List<MessageModel>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(MessageModel.fromDoc).toList());
  }

  // ── Send a message ───────────────────────────────────────────────────────
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'text': trimmed,
      'sentAt': FieldValue.serverTimestamp(),
    });

    // Update last message metadata on the chat doc (useful for future chat list)
    await _db.collection('chats').doc(chatId).set({
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Derive a stable chatId from rideId + passengerId ────────────────────
  // Format: "{rideId}_{passengerId}"
  // The driver and the specific passenger always share the same chat doc.
  static String buildChatId({
    required String rideId,
    required String passengerId,
  }) =>
      '${rideId}_$passengerId';
}
