import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aham/models.dart'; // Assuming ChatInfo is in models.dart

class ChatHistoryService {
  static final _client = Supabase.instance.client;

  /// Fetches all chat sessions for the currently logged-in user from Supabase.
  static Future<List<ChatInfo>> getChats() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('chat_history')
          .select('chat_data')
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      return response.map((item) {
        // The data is stored in the 'chat_data' column.
        final jsonData = item['chat_data'];
        // Supabase might return it as a string or a map, handle both.
        final Map<String, dynamic> chatMap = (jsonData is String) ? jsonDecode(jsonData) : jsonData;
        return ChatInfo.fromJson(chatMap);
      }).toList();
    } catch (e) {
      print('Error fetching chats: $e');
      return [];
    }
  }

  /// Saves or updates a single chat session in Supabase.
  /// This is an "upsert" operation.
  static Future<void> saveChat(ChatInfo chat) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('chat_history').upsert({
        'user_id': userId,
        'chat_id': chat.id,
        'chat_data': chat.toJson(), // Store the entire object as JSON
      }, onConflict: 'user_id, chat_id'); // If chat exists for user, update it
    } catch (e) {
      print('Error saving chat: $e');
    }
  }

  /// Deletes a single chat session from Supabase.
  static Future<void> deleteChat(String chatId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client
          .from('chat_history')
          .delete()
          .match({'user_id': userId, 'chat_id': chatId});
    } catch (e) {
      print('Error deleting chat: $e');
    }
  }
}