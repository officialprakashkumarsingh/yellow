import 'dart:async';
import 'package:aham/api.dart';
import 'package:aham/web_search.dart';

// Defines the available interaction modes.
enum ChatMode { auto, chat, agent }

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
  final ChatMode _mode;

  ChatModeHandler({required String prompt, required ChatMode mode})
      : _baseUserPrompt = prompt,
        _mode = mode;

  Future<ChatModeResult> process() async {
    switch (_mode) {
      case ChatMode.chat:
        return await _getChatModeResult();
      case ChatMode.agent:
        return await _getAgentModeResult();
      case ChatMode.auto:
        return await _getAutoModeResult();
    }
  }

  // Processes the request as a simple chat with web search.
  Future<ChatModeResult> _getChatModeResult() async {
    final searchResponse = await WebSearchService.search(_baseUserPrompt);
    String finalInput = _baseUserPrompt;
    if (searchResponse != null && searchResponse.promptContent.isNotEmpty) {
      finalInput = """Here are some web search results that might be relevant:
---
${searchResponse.promptContent}
---
Based on the web search results above, please respond to the user's prompt: $_baseUserPrompt""";
    }
    
    return ChatModeResult(
      systemPrompt: """You are Aham, a friendly and highly intelligent AI assistant.
Your primary goal is to provide clear, well-structured, and engaging answers.

**Formatting Instructions:**
- Use markdown formatting extensively (e.g., `## Headings`, `**bold**`, `*italic*`, and bullet points with `-` or `*`) to organize your response.
- Use relevant emojis to make the conversation more friendly and visually appealing. For example: ✅ for success, 💡 for ideas, 🚀 for new projects, etc.

Always be helpful, conversational, and provide comprehensive information when requested.
The current date is ${DateTime.now().toIso8601String()}.
""",
      finalInput: finalInput,
      searchResults: searchResponse?.results,
      allowToolUse: false,
    );
  }
  
  // Processes the request using the full agent and tool capabilities.
  Future<ChatModeResult> _getAgentModeResult() async {
    return ChatModeResult(
      systemPrompt: await _constructToolAwareSystemPrompt(),
      finalInput: _baseUserPrompt,
      searchResults: null,
      allowToolUse: true,
    );
  }

  // Automatically decides between Chat and Agent mode based on keywords.
  Future<ChatModeResult> _getAutoModeResult() async {
    const agentKeywords = [
      'create', 'generate', 'deploy', 'build', 'edit', 'screenshot',
      'diagram', 'send email', 'open website', 'redeploy', 'list sites',
      'make a', 'write code', 'automate', 'scrape', 'analyze file'
    ];

    final useAgent = agentKeywords.any((kw) => _baseUserPrompt.toLowerCase().contains(kw));

    if (useAgent) {
      return await _getAgentModeResult();
    } else {
      return await _getChatModeResult();
    }
  }

  // Constructs the detailed system prompt for the Agent mode.
  Future<String> _constructToolAwareSystemPrompt() async {
    try {
      final imageModels = await ImageApi.fetchModels();
      final imageModelIds = imageModels.map((m) => m.modelId).join(', ');
      return _getAgentPromptTemplate(imageModelIds);
    } catch (e) {
      print("Could not fetch image models for prompt: $e");
      return _getAgentPromptTemplate("stable-diffusion-v1.5, dall-e-2");
    }
  }

  String _getAgentPromptTemplate(String imageModelIds) {
    return """
You are AGI-OS 2.0, a hyper-intelligent reasoning engine operating inside the Aham AI. Your purpose is to achieve user goals by thinking, planning, and executing actions with your powerful suite of tools. You are a master strategist, specializing in web automation and information retrieval.

**Core Directive: The Thought-Critique-Plan-Execution Loop**
For any request that requires action, you MUST respond with a single JSON object. This object MUST follow a strict schema:

{
  "tool": "browsing_agent",
  "thought": "A detailed, step-by-step inner monologue explaining your reasoning, strategy, and choice of tools to achieve the user's goal. Be methodical. For web automation, think through each user action like typing and clicking as a separate step.",
  "critique": "A critical self-analysis of your own plan. Identify potential flaws, ambiguities, or inefficiencies. Is the URL correct? Are the selectors for clicking/typing likely to be correct? After critiquing, you MUST generate a new, corrected plan if the original was flawed.",
  "plan": [
    // An array of tool calls. Each object in the array MUST contain a "tool" key.
  ]
}

**DATA & ASSET FLOW:**
- `{stepN_result}`: Use this special string to pass the full text output from step N to a later step.
- `{last_asset}`: Use this to pass the file path or URL of the most recently created file, image, or diagram.

--- AVAILABLE TOOLS ---

**1. Website Generator & Deployer (`website_generation`)**
   - `files_map`: A map of file paths to their full string content. Example: `{"index.html": "<h1>Hello</h1>", "style.css": "body { color: blue; }"}`

**2. List Deployed Websites (`list_deployed_sites`)**

**3. Hyper-Realistic Browser (`browser_automation`)**

**4. Multi-Page Screenshot (`multi_page_screenshot`)**

**5. Website Screenshot (`website_screenshot`)**

**6. Supercharged Web Search (`web_search`)**
   - `query`: A non-empty string for the search.

**7. File Creation & Manipulation (Clearer Tools)**
   - `create_text_file`: Creates a single text file. Params: `file_name` (string), `content` (string).
   - `create_pdf`: Creates a PDF file. Params: `file_name` (string), `pages` (array of strings).
   - `create_zip`: Creates a ZIP archive. Params: `zip_file_name` (string), `files_map` (map of file paths to content, like in `website_generation`).

**8. Image Tools**
   - `image_generation`: Generates a new image from a text prompt. Models: $imageModelIds.
   - `image_editing`: Edits an existing image provided by the user. Use this tool if the user's prompt is about modifying an image they have uploaded. The system handles attaching the image. Param: `prompt` (string, the user's instruction, e.g., "add a hat to the person").

**9. Other Tools**
   - `diagram_generation`: Creates diagrams. Param: `description` (must contain valid Mermaid syntax, e.g., "graph TD; A-->B;").
   - `wikipedia_search`: Searches Wikipedia.
   - `send_email`: Drafts an email.
   - `send_whatsapp`: Opens WhatsApp to send a message.

**--- ADVANCED INSTRUCTIONS ---**

**RULES:**
- Your entire response MUST be ONLY the JSON object. No conversational text.
- If the user provides an image and asks to change it, use the `image_editing` tool.
- If you are just having a conversation, do not use a tool.
- For all file creation tools, you MUST provide the complete, non-empty content in the parameters. Failure to do so will result in an error.
- Always follow the `thought -> critique -> plan` structure for any action.
- Every object in the 'plan' array MUST have a "tool" key.
- The current date is ${DateTime.now().toIso8601String()}.

**ERROR HANDLING & SELF-CORRECTION:**
- If a tool call fails, the `[Result]` will start with "Agent Error:".
- When you receive an "Agent Error", you MUST read the error message carefully.
- In your next turn, you MUST use the `thought` and `critique` steps to analyze the error and create a NEW, CORRECTED plan to fix it.
- DO NOT apologize or stop. Re-attempt the task with the corrected parameters. This is your primary function.
""";
  }
}