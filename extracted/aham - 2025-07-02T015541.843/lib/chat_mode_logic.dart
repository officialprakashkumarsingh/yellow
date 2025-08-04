import 'dart:async';
import 'package:ahamai/api.dart';
import 'package:ahamai/web_search.dart';

// Defines the available interaction modes.
enum ChatMode { auto, chat }

// A result class to hold the outcome of the mode processing.
class ChatModeResult {
  final String systemPrompt;
  final String finalInput;
  final List<SearchResult>? searchResults;
  final bool allowToolUse;

  ChatModeResult({
    required this.systemPrompt,
    required this.finalInput,
    this.searchResults,
    required this.allowToolUse,
  });
}

// Handles the logic for determining which mode to use.
class ChatModeHandler {
  final String _baseUserPrompt;
  final ChatMode mode;

  ChatModeHandler({
    required String prompt,
    required this.mode,
  }) : _baseUserPrompt = prompt;

  Future<ChatModeResult> process() async {
    switch (mode) {
      case ChatMode.auto:
      case ChatMode.chat:
      default:
        return await _getChatModeResult();
    }
  }

  // Simple chat mode with screenshot capability
  Future<ChatModeResult> _getChatModeResult() async {
    return ChatModeResult(
      systemPrompt: """You are AhamAI, a friendly and highly intelligent AI assistant.
Your primary goal is to provide clear, well-structured, and engaging answers.

**Formatting Instructions:**
- Use markdown formatting extensively (e.g., `## Headings`, `**bold**`, `*italic*`, and bullet points with `-` or `*`) to organize your response.
- Use relevant emojis to make the conversation more friendly and visually appealing. For example: ✅ for success, 💡 for ideas, 🚀 for new projects, etc.

**Screenshot Capability:**
- You can show website screenshots by using this URL pattern: `https://s0.wp.com/mshots/v1/https%3A%2F%2F[ENCODED_URL]?w=1280&h=720`
- Remember to URL encode the website address (replace `/` with `%2F`, `:` with `%3A`, etc.)
- Example: For google.com: `https://s0.wp.com/mshots/v1/https%3A%2F%2Fgoogle.com?w=1280&h=720`

Always be helpful, conversational, and provide comprehensive information when requested.
The current date is ${DateTime.now().toIso8601String()}.
""",
      finalInput: _baseUserPrompt,
      searchResults: null,
      allowToolUse: false,
    );
  }
}