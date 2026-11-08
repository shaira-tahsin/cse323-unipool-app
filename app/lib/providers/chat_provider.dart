import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/chat_repository.dart';
import '../data/models/message_model.dart';

// ── Singleton repository ─────────────────────────────────────────────────
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository();
});

// ── Real-time messages stream for a given chatId ─────────────────────────
final messagesStreamProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.messagesStream(chatId);
});
