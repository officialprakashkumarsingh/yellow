import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:aham/openai_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:aham/api.dart';
import 'package:aham/chat_ui_helpers.dart';
import 'package:aham/file_processing.dart';
import 'package:aham/image_editor.dart';
import 'package:aham/logincredits.dart';
import 'package:aham/models.dart';
import 'package:aham/theme.dart';
import 'package:aham/ui_widgets.dart';
import 'package:aham/web_search.dart';
import 'package:aham/tools.dart';
import 'package:aham/chat_mode_logic.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatScreen extends StatefulWidget {
  final List<ChatMessage>? initialMessages;
  final String? initialMessage;
  final String? chatId;
  final String? chatTitle;
  final String? category;
  final bool isPinned;
  final bool isGenerating;
  final bool isStopped;
  final StreamController<ChatInfo> chatInfoStream;

  const ChatScreen({super.key, this.initialMessages, this.initialMessage, this.chatId, this.chatTitle, this.category, this.isPinned = false, this.isGenerating = false, this.isStopped = false, required this.chatInfoStream});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<ChatMessage> _messages;

  bool _isStreaming = false;
  bool _isStoppedByUser = false;
  bool _isSending = false;
  
  ChatMode _chatMode = ChatMode.auto;

  late String _selectedChatModelId;
  bool _isModelSetupComplete = false;

  StreamSubscription? _streamSubscription;
  http.Client? _httpClient;

  late String _chatId;
  late bool _isPinned;
  late String _chatTitle;
  late String _category;
  List<SearchResult>? _lastSearchResults;

  ChatAttachment? _attachment;
  XFile? _attachedImage;
  bool _isProcessingFile = false;

  bool _showScrollButton = false;

  bool _didRedirectForTool = false;
  String? _lastCreatedImageUrl;
  String? _lastCreatedFilePath;

  final Map<String, String> _agentMemory = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messages = widget.initialMessages != null ? List.from(widget.initialMessages!) : [];
    _isPinned = widget.isPinned;
    _chatId = widget.chatId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _chatTitle = widget.chatTitle ?? "New Chat";
    _category = widget.category ?? 'General';

    if (_chatTitle == "New Chat" && _messages.isNotEmpty) {
      final firstUserMessage = _messages.firstWhere((m) => m.role == 'user', orElse: () => ChatMessage(role: 'user', text: '', timestamp: DateTime.now()));
      _chatTitle = firstUserMessage.text.length > 30 ? '${firstUserMessage.text.substring(0, 30)}...' : firstUserMessage.text.trim().isEmpty ? "New Chat" : firstUserMessage.text;
    }

    _isStreaming = false;
    _isStoppedByUser = false;

    _initialize();
    
    _controller.addListener(() {
      setState(() {});
    });

    _scrollController.addListener(() {
      final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200;
      if (!isAtBottom) {
        if (!_showScrollButton) setState(() => _showScrollButton = true);
      } else {
        if (_showScrollButton) setState(() => _showScrollButton = false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _didRedirectForTool) {
      setState(() {
        _addMessageToList(ChatMessage(
          role: 'model',
          text: 'External action completed.',
          type: MessageType.text,
          timestamp: DateTime.now(),
        ));
        _didRedirectForTool = false;
      });
      _updateChatInfo(false, false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _streamSubscription?.cancel();
    _httpClient?.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _setupChatModel();
    _isModelSetupComplete = true;

    if (widget.initialMessage != null && mounted) {
      _controller.text = widget.initialMessage!;
      await _sendMessage(widget.initialMessage!);
    }
  }

  Future<void> _setupChatModel() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!ApiConfigService.instance.isInitialized) {
        await ApiConfigService.instance.initialize();
    }
    _selectedChatModelId = prefs.getString('chat_model') ?? ApiConfigService.instance.defaultModelId;

    // Vision capabilities are now handled by the unified OpenAI service
    // No separate model initialization needed

    if (mounted) setState(() {});
  }

  void _addMessageToList(ChatMessage message) {
    if (!mounted) return;

    if ((message.type == MessageType.image && message.imageUrl != null) || (message.type == MessageType.file && message.filePath != null)) {
      final lastMessageIndex = _messages.lastIndexWhere((m) => m.role == 'model');
      if (lastMessageIndex != -1) {
        final lastMessage = _messages[lastMessageIndex];
        if (lastMessage.type == message.type && lastMessage.imageUrl == null && lastMessage.filePath == null) {
          setState(() {
            _messages[lastMessageIndex] = message;
          });
          return;
        }
      }
    }
    
    final int index = _messages.length;
    _messages.add(message);
    _listKey.currentState?.insertItem(index, duration: const Duration(milliseconds: 300));
  }

  void _removeMessagesFrom(int startIndex) {
    if (!mounted) return;
    final int itemsToRemove = _messages.length - startIndex;
    if (itemsToRemove <= 0) return;

    for (int i = 0; i < itemsToRemove; i++) {
      final int indexToRemove = _messages.length - 1;
      final ChatMessage removedItem = _messages.removeLast();
      _listKey.currentState?.removeItem(indexToRemove, (context, animation) => _buildAnimatedItem(removedItem, indexToRemove, animation, _messages.length, isRemoving: true), duration: const Duration(milliseconds: 200));
    }
  }

  Future<void> _sendMessage(String input) async {
    if (!_isModelSetupComplete || _isStreaming || _isSending) return;
    if (input.trim().isEmpty && _attachment == null && _attachedImage == null) return;
    
    setState(() => _isSending = true);
    
    _httpClient = http.Client();

    try {
      final currentCredits = await CreditService.instance.getCredits();
      if (currentCredits < 5) {
        _showStyledSnackBar(message: 'You need at least 5 credits to send a message.', isError: true);
        _httpClient?.close();
        return;
      }
      
      await CreditService.instance.deductCredits(5);
  
      final modelConfig = ApiConfigService.instance.getModelConfigById(_selectedChatModelId);
      bool isAgentModel = modelConfig?.type == 'openai_compatible';

      if (_attachedImage != null && !isAgentModel) {
        _httpClient?.close();
        await _sendVisionMessage(input, _attachedImage!);
      } else {
        await _sendTextMessage(input);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _handleStreamChunk(String textChunk) {
    if (_isStoppedByUser) {
      _streamSubscription?.cancel();
      return;
    }

    if (_messages.isNotEmpty && _messages.last.role == 'model' && _messages.last.text.isEmpty) {
       setState(() {});
    }

    if (_messages.isNotEmpty && _messages.last.role == 'model') {
      final lastMessage = _messages.last;
      final updatedMessage = ChatMessage(
        role: lastMessage.role,
        text: lastMessage.text + textChunk,
        searchResults: _lastSearchResults,
        timestamp: lastMessage.timestamp,
        type: lastMessage.type,
      );
      setState(() {
        _messages[_messages.length - 1] = updatedMessage;
      });
      _smoothScrollToBottom();
    }
  }

  Future<void> _sendVisionMessage(String input, XFile imageFile) async {
    if (_geminiVisionModel == null) {
      _onStreamingError("Vision model is not configured.");
      return;
    }
    _isStoppedByUser = false;
    _lastSearchResults = null;
    final imageBytes = await imageFile.readAsBytes();
    final userMessage = ChatMessage(role: 'user', text: input, imageBytes: imageBytes, timestamp: DateTime.now());

    setState(() { _isStreaming = true; _attachedImage = null; });

    _addMessageToList(userMessage);
    _addMessageToList(ChatMessage(role: 'model', text: '', imageBytes: imageBytes, timestamp: DateTime.now()));
    _controller.clear();
    _smoothScrollToBottom();
    _updateChatInfo(true, false);

    try {
      // Use OpenAI service for vision capabilities
      final responseStream = await OpenAIService.instance.streamChatCompletion(
        prompt: input,
        messages: _messages.take(_messages.length - 2).toList(), // Exclude the last two messages (user and empty assistant)
        imageBytes: imageBytes,
        modelId: _selectedChatModelId,
      );
      
      _streamSubscription = responseStream.listen(
        (chunk) => _handleStreamChunk(chunk),
        onDone: _onStreamingDone,
        onError: _onStreamingError,
        cancelOnError: true,
      );
    } catch(e) {
      _onStreamingError(e);
    }
  }

  Future<void> _sendTextMessage(String input) async {
    if (input.trim().isEmpty && _attachment == null && _attachedImage == null) {
      _showStyledSnackBar(message: 'Please provide a prompt.', isError: true);
      return;
    }
    _isStoppedByUser = false;
    _lastSearchResults = null;

    String finalInputForAI = input;
    if (_attachment != null) {
      finalInputForAI = """CONTEXT FROM THE FILE '${_attachment!.fileName}':
---
${_attachment!.content}
---
Based on the context above, answer the following prompt: $input""";
    } else if (_attachedImage != null) {
      finalInputForAI = "[An image has been uploaded by the user. If the prompt is a request to modify this image, use the `image_editing` tool. If the prompt is asking to describe or analyze the image, state that you need a Vision-enabled model for that task, as your current capability is text and tool-based.]\n\nUser Prompt: $input";
    }

    final userMessage = ChatMessage(
        role: 'user',
        text: input,
        imageBytes: _attachedImage != null ? await _attachedImage!.readAsBytes() : null,
        attachedFileName: _attachment?.fileName,
        attachedContainedFiles: _attachment?.containedFileNames,
        timestamp: DateTime.now());

    setState(() {
      _isStreaming = true;
      if (_chatTitle == "New Chat" || _chatTitle.trim().isEmpty) {
        _chatTitle = userMessage.text.length > 30 ? '${userMessage.text.substring(0, 30)}...' : userMessage.text;
      }
      if (_messages.isEmpty) _category = "General";
      _attachment = null;
      _attachedImage = null; 
    });

    _addMessageToList(userMessage);
    _controller.clear();
    _smoothScrollToBottom();
    _updateChatInfo(true, false);

    _addMessageToList(ChatMessage(role: 'model', text: '', attachedFileName: userMessage.attachedFileName, timestamp: DateTime.now()));
    _smoothScrollToBottom();

    final modelConfig = ApiConfigService.instance.getModelConfigById(_selectedChatModelId);
    if (modelConfig == null) {
      _onStreamingError("Model configuration not found. Please check your settings.");
      return;
    }
    
    // Use the new ChatModeHandler to determine logic
    final handler = ChatModeHandler(prompt: finalInputForAI, mode: _chatMode);
    final modeResult = await handler.process();

    _lastSearchResults = modeResult.searchResults;
    
    await _sendOpenAICompatibleStream(
      modeResult.finalInput,
      systemPrompt: modeResult.systemPrompt,
    );
  }

  Future<void> _sendOpenAICompatibleStream(String input, {String? toolExecutionReport, String? overrideApiUrl, int redirectCount = 0, required String systemPrompt}) async {
    if (redirectCount > 5) {
      _onStreamingError("Too many redirects. Aborting request.");
      return;
    }
    
    if (_httpClient == null) {
      _onStreamingError("An internal error occurred: HTTP client was not initialized.");
      return;
    }

    try {
      final config = ApiConfigService.instance.selectedModel;
      
      String apiUrl = overrideApiUrl ?? '${config.apiUrl}/v1/chat/completions';
      String apiKey = config.apiKey!;
      String modelName = config.modelId;
      
      String finalSystemPrompt = systemPrompt;

      if(toolExecutionReport != null && toolExecutionReport.isNotEmpty) {
        final agentSystemPrompt = await ChatModeHandler(prompt: '', mode: ChatMode.agent).process().then((r) => r.systemPrompt);
        finalSystemPrompt = """$agentSystemPrompt
---
AGENT EXECUTION REPORT:
$toolExecutionReport
---
**CRITICAL INSTRUCTION:** The user's request has been fulfilled by the tools. Your ONLY task now is to synthesize the results from the report above into a final, comprehensive, and user-friendly answer. 
**DO NOT** output any more tool calls or JSON. Your response must be the final answer for the user in plain text or Markdown.
Based on the successful execution of your plan, provide the final synthesized answer to the user's original request: $input""";
      }

      final history = _messages.map((m) => {"role": m.role == 'user' ? "user" : "assistant", "content": m.text}).toList();
      history.removeLast();
      history.removeLast();
      
      List<Map<String, dynamic>> messagesForApi = [
        {"role": "system", "content": finalSystemPrompt},
        ...history.map((m) => m),
        {"role": "user", "content": input}
      ];

      final request = http.Request('POST', Uri.parse(apiUrl))
        ..headers.addAll({
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $apiKey'
        })
        ..encoding = utf8
        ..body = jsonEncode({
          'model': modelName, 
          'messages': messagesForApi, 
          'stream': true,
          'max_tokens': 4096,
          'temperature': 0.7, 
        });

      final response = await _httpClient!.send(request).timeout(const Duration(minutes: 3));

      if ([301, 302, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location != null) {
          await _sendOpenAICompatibleStream(input, toolExecutionReport: toolExecutionReport, overrideApiUrl: location, redirectCount: redirectCount + 1, systemPrompt: systemPrompt);
        } else {
          _onStreamingError("HTTP Redirect (Code: ${response.statusCode}) with no location header.");
        }
        return;
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        String errorMessage = "API Error (${response.statusCode})";
        try {
          final decodedError = jsonDecode(errorBody);
          final message = decodedError['error']?['message'] ?? decodedError['detail'] ?? 'No details provided.';
          errorMessage += "\nDetails: $message";
        } catch (e) {
          errorMessage += "\nDetails: ${errorBody.substring(0, (errorBody.length > 200) ? 200 : errorBody.length)}...";
        }
        _onStreamingError(errorMessage);
        return;
      }

      String buffer = '';
      _streamSubscription = response.stream.transform(utf8.decoder).listen(
        (chunk) {
          if (_isStoppedByUser) { _streamSubscription?.cancel(); return; }
          buffer += chunk;
          while (true) {
            final lineEnd = buffer.indexOf('\n');
            if (lineEnd == -1) break;
            final line = buffer.substring(0, lineEnd).trim();
            buffer = buffer.substring(lineEnd + 1);
            if (line.startsWith('data: ')) {
              final data = line.substring(6);
              if (data == '[DONE]') return;
              try {
                final parsed = jsonDecode(data);
                final content = parsed['choices']?[0]?['delta']?['content'];
                if (content != null) {
                  _handleStreamChunk(content);
                }
              } catch (e) { /* Ignore */ }
            }
          }
        },
        onDone: () {
          if (buffer.isNotEmpty && !_isStoppedByUser) {
            try {
               final lines = buffer.split('\n').where((l) => l.startsWith('data: '));
               for (final line in lines) {
                 final data = line.substring(6).trim();
                 if (data.isNotEmpty && data != '[DONE]') {
                   final parsed = jsonDecode(data);
                   final content = parsed['choices']?[0]?['delta']?['content'];
                   if (content != null) {
                    _handleStreamChunk(content);
                   }
                 }
               }
            } catch(e) {
              print("Error parsing final buffer chunk: $e");
            }
          }
          _onStreamingDone();
        },
        onError: _onStreamingError,
        cancelOnError: true,
      );
    } on TimeoutException catch (_) {
      _onStreamingError("The request timed out. The server took too long to respond. Please try a simpler request.");
    } on http.ClientException catch (e) {
      _onStreamingError(e);
    } catch (e) {
      _onStreamingError("An unexpected error occurred: $e");
    }
  }

  void _addAgentStatusMessage(String text, IconData icon) {
     _addMessageToList(ChatMessage(
        role: 'model',
        text: text,
        type: MessageType.agent_status,
        timestamp: DateTime.now(),
        statusIcon: icon,
      ));
      _smoothScrollToBottom();
  }
  
  Future<void> _executeAgentPlan(String originalUserPrompt, Map<String, dynamic> agentResponse) async {
    final plan = agentResponse['plan'] as List<dynamic>?;
    if (plan == null) {
      _onStreamingError("Agent Error: Plan is missing.");
      return;
    }
    
    final userMessage = _messages.lastWhere((m) => m.role == 'user');
    final userImage = userMessage.imageBytes != null ? XFile.fromData(userMessage.imageBytes!, name: 'user_image.jpg') : null;
    
    final toolExecutor = ToolExecutor(
        context: context,
        onAddMessage: _addMessageToList,
        onUpdateAssets: (imageUrl, filePath) {
          if (imageUrl != null) _lastCreatedImageUrl = imageUrl;
          if (filePath != null) _lastCreatedFilePath = filePath;
        },
        agentMemory: _agentMemory,
        userImage: userImage
    );

    final thought = agentResponse['thought'] as String?;
    final critique = agentResponse['critique'] as String?;

    _removeMessagesFrom(_messages.length - 1);
    if (thought != null) _addAgentStatusMessage("[Thought]\n$thought", CupertinoIcons.lightbulb);
    if (critique != null) _addAgentStatusMessage("[Critique]\n$critique", Icons.gavel_rounded);

    List<String> stepResults = [];
    var finalReport = StringBuffer("Autonomous Agent Execution Report:\n\n");
    String? currentUrl;

    for (int i = 0; i < plan.length; i++) {
      var step = plan[i];
      if (step is! Map<String, dynamic>) {
        stepResults.add("Error: Step ${i+1} was not a valid object.");
        continue;
      }
      
      if (step['url'] is String) currentUrl = step['url'];

      String stepJson = jsonEncode(step);
      for (int j = 0; j < stepResults.length; j++) {
        stepJson = stepJson.replaceAll('"{step${j+1}_result}"', jsonEncode(stepResults[j]));
      }
      String? lastAssetPath = _lastCreatedImageUrl ?? _lastCreatedFilePath;
      if (lastAssetPath != null) {
        stepJson = stepJson.replaceAll('"{last_asset}"', jsonEncode(lastAssetPath));
      }
      for (final entry in _agentMemory.entries) {
        stepJson = stepJson.replaceAll('"{memory:${entry.key}}"', jsonEncode(entry.value));
      }
      final hydratedStep = jsonDecode(stepJson) as Map<String, dynamic>;

      final tool = hydratedStep['tool'] as String?;
      if (tool == null) {
          String errorResult = "Agent Error: Missing 'tool' in step ${i+1}.";
          _addAgentStatusMessage(errorResult, Icons.error_outline_rounded);
          stepResults.add(errorResult);
          finalReport.writeln("--- Step ${i+1}: FAILED ---\nResult: $errorResult\n");
          continue;
      }

      _addAgentStatusMessage("[Executing: $tool]", Icons.play_arrow_rounded);
      
      final currentStepResult = await toolExecutor.executeTool(hydratedStep, currentUrl: currentUrl);

      stepResults.add(currentStepResult);
      final icon = currentStepResult.startsWith('[SCRAPED_CONTENT_START]') ? Icons.article_outlined : Icons.check_circle_outline;
      _addAgentStatusMessage("[Result]\n$currentStepResult", icon);
      finalReport.writeln("--- Step ${i+1}: $tool ---\nResult: $currentStepResult\n");
      
      if(currentStepResult.startsWith("Agent Error:")) {
        break; 
      }
    }

    _addMessageToList(ChatMessage(role: 'model', text: '', timestamp: DateTime.now()));
    _smoothScrollToBottom();

    await _sendOpenAICompatibleStream(originalUserPrompt, toolExecutionReport: finalReport.toString(), systemPrompt: await ChatModeHandler(prompt: '', mode: ChatMode.agent).process().then((r) => r.systemPrompt));
  }
  
  Future<bool> _handleToolCall(String responseText, String originalUserPrompt) async {
    final handler = ChatModeHandler(prompt: originalUserPrompt, mode: _chatMode);
    final modeResult = await handler.process();
    if (!modeResult.allowToolUse) return false;

    String? jsonString;
    final jsonRegex = RegExp(r"```json\s*([\s\S]*?)\s*```|({[\s\S]*})");
    final match = jsonRegex.firstMatch(responseText);

    if (match != null) {
      jsonString = match.group(1) ?? match.group(0);
    }
    
    if (jsonString != null && jsonString.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonString.trim());
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('plan') && decoded.containsKey('thought')) {
            await _executeAgentPlan(originalUserPrompt, decoded);
            return true;
          } else if (decoded.containsKey('tool')) {
            final userMessage = _messages.lastWhere((m) => m.role == 'user');
            final userImage = userMessage.imageBytes != null ? XFile.fromData(userMessage.imageBytes!, name: 'user_image.jpg') : null;

            final toolExecutor = ToolExecutor(
                context: context,
                onAddMessage: _addMessageToList,
                onUpdateAssets: (imageUrl, filePath) {
                  if (imageUrl != null) _lastCreatedImageUrl = imageUrl;
                  if (filePath != null) _lastCreatedFilePath = filePath;
                },
                agentMemory: _agentMemory,
                userImage: userImage);

            _removeMessagesFrom(_messages.length - 1);
            final tool = decoded['tool'] as String;
            _addAgentStatusMessage("[Executing: $tool]", Icons.play_arrow_rounded);
            final result = await toolExecutor.executeTool(decoded);
            
            if (tool != 'list_deployed_sites' && tool != 'image_editing' && tool != 'image_generation') {
              _addAgentStatusMessage("[Result]\n$result", Icons.check_circle_outline);
            }
            await _sendOpenAICompatibleStream(originalUserPrompt, toolExecutionReport: "--- Step 1: $tool ---\nResult: $result\n", systemPrompt: await ChatModeHandler(prompt: '', mode: ChatMode.agent).process().then((r) => r.systemPrompt));
            
            return true;
          }
        }
      } catch (e) {
        print("JSON decoding failed: $e. Checking for plain text agent response.");
      }
    }

    if (responseText.contains('[Thought]') || responseText.contains('[Critique]')) {
       _removeMessagesFrom(_messages.length - 1);
       final parts = responseText.split(RegExp(r'(\[Thought\]|\[Critique\])')).where((s) => s.isNotEmpty).toList();
       String finalMessage = '';
       
       for(int i = 0; i < parts.length; i++) {
         String part = parts[i].trim();
         if(part.toLowerCase() == '[thought]') {
           if(i + 1 < parts.length) {
             _addAgentStatusMessage('[Thought]\n' + parts[i+1].trim(), CupertinoIcons.lightbulb);
             i++;
           }
         } else if (part.toLowerCase() == '[critique]') {
            if(i + 1 < parts.length) {
              _addAgentStatusMessage('[Critique]\n' + parts[i+1].trim(), Icons.gavel_rounded);
              i++;
            }
         } else {
           finalMessage += part + '\n';
         }
       }
       
       if (finalMessage.trim().isNotEmpty) {
         _addMessageToList(ChatMessage(role: 'model', text: finalMessage.trim(), timestamp: DateTime.now()));
       }
       return true;
    }

    return false;
  }

  void _onStreamingDone() {
    _finalizeStream();
  }

  void _onStreamingError(dynamic error) {
    _finalizeStream(error: error);
  }
  
  Future<void> _finalizeStream({dynamic error}) async {
    if (!mounted) {
      _httpClient?.close();
      return;
    }

    if (error != null) {
      print("Aham Streaming Error: $error");
      if (_messages.isNotEmpty && _messages.last.role == 'model') {
        final errorMessage = error is http.ClientException
            ? '❌ Error: ${error.message}'
            : '❌ Error: $error';
        _messages[_messages.length - 1] = ChatMessage(role: 'model', text: errorMessage, timestamp: DateTime.now());
      }
      setState(() { _isStreaming = false; });
      _httpClient?.close();
      _httpClient = null;
      _updateChatInfo(false, false);
      _smoothScrollToBottom();
      return;
    }
    
    if (_messages.isEmpty || _messages.last.role != 'model') {
       setState(() { _isStreaming = false; });
       _httpClient?.close();
       _httpClient = null;
       _updateChatInfo(false, false);
       return;
    }

    final lastMessageText = _messages.last.text.trim();
    final lastUserMessage = _messages.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage(role: 'user', text: '', timestamp: DateTime.now()));

    bool toolWasCalled = await _handleToolCall(lastMessageText, lastUserMessage.text);
    
    if (!mounted) {
      if (!toolWasCalled) _httpClient?.close();
      return;
    }

    if (toolWasCalled) {
      return;
    }

    _httpClient?.close();
    _httpClient = null;

    if (lastMessageText.isEmpty) {
      _removeMessagesFrom(_messages.length - 1);
    } else {
      final lastMessage = _messages.last;
      final finalMessage = ChatMessage(
          role: lastMessage.role,
          text: lastMessageText,
          searchResults: _lastSearchResults,
          timestamp: lastMessage.timestamp,
          type: lastMessage.type,
      );
      setState(() => _messages[_messages.length - 1] = finalMessage);
    }
    
    setState(() {
      _isStreaming = false;
      _isStoppedByUser = false; 
    });
    _updateChatInfo(false, false);
    _smoothScrollToBottom();
  }

  void _updateChatInfo(bool isGenerating, bool isStopped) {
    final chatInfo = ChatInfo(id: _chatId, title: _chatTitle, messages: List.from(_messages), isPinned: _isPinned, isGenerating: isGenerating, isStopped: isStopped, category: _category);
    widget.chatInfoStream.add(chatInfo);
  }

  void _stopStreaming() {
    if (_isStoppedByUser) return;
    _isStoppedByUser = true;
    _streamSubscription?.cancel();
    _finalizeStream(error: "Response generation stopped.");
  }

  void _smoothScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100;
        if (isAtBottom) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.linear,
          );
        }
      }
    });
  }

  void _forceScrollToBottom() {
     WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showStyledSnackBar({required String message, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 110, left: 16, right: 16),
        content: GlassmorphismPanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                  color: isError ? Colors.redAccent : Colors.greenAccent,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showStyledSnackBar(message: 'Copied to clipboard');
  }

  Future<void> _regenerateResponse(int userMessageIndex) async {
    if (userMessageIndex < 0 || userMessageIndex >= _messages.length) return;
    final userMessage = _messages[userMessageIndex];
    if (userMessage.role != 'user') return;

    _removeMessagesFrom(userMessageIndex + 1);
    
    final messageText = userMessage.text;
    final messageImageBytes = userMessage.imageBytes;

    setState(() => _isSending = true);
    try {
        final currentCredits = await CreditService.instance.getCredits();
        if (currentCredits < 5) {
            _showStyledSnackBar(message: 'You need at least 5 credits to regenerate a response.', isError: true);
            return;
        }
        await CreditService.instance.deductCredits(5);

        if (messageImageBytes != null) {
          _attachedImage = XFile.fromData(messageImageBytes, name: 'image.jpg');
        }

        await _sendMessage(messageText);

    } finally {
        if(mounted) {
            setState(() => _isSending = false);
        }
    }
  }

  void _showUserMessageOptions(BuildContext context, ChatMessage message, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassmorphismPanel(
        isBottomSheet: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.content_copy_outlined), title: const Text('Copy Message'), onTap: () { Navigator.pop(context); _copyToClipboard(message.text); }),
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit and Resend'), onTap: () { Navigator.pop(context); setState(() { _controller.text = message.text; _removeMessagesFrom(index); _stopStreaming(); }); }),
              SizedBox(height: MediaQuery.of(context).padding.bottom)
            ]
          ),
        ),
      )
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    try {
      final image = await ImagePicker().pickImage(source: source);
      if (image != null) {
        setState(() {
          _isProcessingFile = true;
          _attachedImage = null;
          _attachment = null;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {
          _isProcessingFile = false;
          _attachedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingFile = false);
        _showStyledSnackBar(message: 'Error picking image: $e', isError: true);
      }
    }
  }

  Future<void> _pickAndProcessFile() async {
    Navigator.pop(context);
    setState(() => _isProcessingFile = true);
    try {
      final attachment = await FileProcessingService.pickAndProcessFile();
      if (mounted) {
        if (attachment != null) {
          setState(() {
            _attachment = attachment;
            _attachedImage = null;
            _isProcessingFile = false;
          });
          _showStyledSnackBar(message: '"${attachment.fileName}" uploaded and ready.');
        } else {
          setState(() => _isProcessingFile = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingFile = false);
        _showStyledSnackBar(message: 'Error reading file: $e', isError: true);
      }
    }
  }

  void _showToolsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassmorphismPanel(
        isBottomSheet: true,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) => Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [FileSourceButton(icon: CupertinoIcons.camera, label: 'Camera', onTap: () => _pickImage(ImageSource.camera)), FileSourceButton(icon: CupertinoIcons.photo, label: 'Photos', onTap: () => _pickImage(ImageSource.gallery)), FileSourceButton(icon: CupertinoIcons.folder, label: 'Files', onTap: _pickAndProcessFile)]),
                const Divider(height: 32),
                ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.language_outlined), title: const Text('View Deployed Sites'), onTap: () { Navigator.pop(context); _sendMessage("List my deployed sites"); }),
                ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.image_outlined), title: const Text('Create an image'), onTap: () { Navigator.pop(context); _showImagePromptDialog(); }),
                SizedBox(height: MediaQuery.of(context).padding.bottom)
              ]
            )
          )
        ),
      )
    );
  }

  void _showImagePromptDialog() async {
    final TextEditingController promptController = TextEditingController();
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => StyledDialog(
          title: 'Image Topic',
          contentWidget: TextField(
            controller: promptController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g., An astronaut on a horse'),
            onSubmitted: (prompt) {
               if (prompt.trim().isNotEmpty) {
                Navigator.of(context).pop();
                _sendMessage("Create an image of: $prompt");
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final prompt = promptController.text;
                if (prompt.trim().isNotEmpty) {
                  Navigator.of(context).pop();
                  _sendMessage("Create an image of: $prompt");
                }
              },
              child: const Text('Generate'),
            ),
          ],
        ),
    );
  }

  Widget _buildAnimatedItem(ChatMessage message, int index, Animation<double> animation, int totalMessageCount, {bool isRemoving = false}) {
    return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: isRemoving ? Curves.easeOut : Curves.easeIn), child: _buildMessage(message, index, totalMessageCount),);
  }

  final kMessageTextStyle = const TextStyle(fontSize: 15.5, height: 1.45);

  Widget _buildMessage(ChatMessage message, int index, int totalMessageCount) {
    if (message.type == MessageType.scraped_content) {
      return ScrapedContentMessage(message: message);
    }
    
    if (message.text.startsWith('Here are your deployed sites:')) {
      return DeployedSitesListMessage(
        message: message,
        onEdit: (String name, String siteId) {
          setState(() {
            _chatMode = ChatMode.agent;
            _controller.text = 'Redeploy the site "$name" (ID: $siteId) with the following changes: ';
            _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
          });
        },
      );
    }

    if (message.type == MessageType.agent_status) {
      if (message.text.contains('[SCRAPED_CONTENT_START]')) {
        return const SizedBox.shrink();
      }
      
      IconData icon;
      if (message.text.startsWith('[Thought]')) icon = CupertinoIcons.lightbulb;
      else if (message.text.startsWith('[Critique]')) icon = Icons.gavel_rounded;
      else if (message.text.startsWith('[Executing:')) icon = Icons.play_arrow_rounded;
      else if (message.text.startsWith('[Result]')) icon = Icons.check_circle_outline;
      else icon = Icons.info_outline;
      
      return AgentStatusMessage(message: ChatMessage(
        role: message.role, text: message.text, timestamp: message.timestamp, statusIcon: icon
      ));
    }
    
    if (message.role == 'model' && !((_isStreaming || _isSending) && index == _messages.length - 1) ) {
      if (message.type == MessageType.image && message.imageUrl != null) {
        return ImageMessage(
          message: message,
          onShowSnackbar: (String msg, {bool isError = false}) => _showStyledSnackBar(message: msg, isError: isError),
        );
      }
      if (message.type == MessageType.image && message.filePath != null) {
         return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: Image.file(
                  File(message.filePath!),
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.error_outline, color: Colors.red, size: 40),
                ),
              ),
            ),
          ),
        );
      }
      if (message.type == MessageType.presentation && message.slides != null) {
        return PresentationMessage(message: message);
      }
      if (message.type == MessageType.file && message.filePath != null) {
        return FileMessageWidget(message: message);
      }
      if (message.text.startsWith('❌') || message.text.contains('created successfully!') || message.text == 'External action completed.') {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
            child: Text(message.text, style: kMessageTextStyle.copyWith(color: message.text.startsWith('❌') ? Colors.redAccent : Theme.of(context).colorScheme.onSurface)),
          ),
        );
      }
    }

    if (message.role == 'model' && message.text.isEmpty && index == _messages.length -1) {
        if (message.type == MessageType.image) return const ImageShimmer();
        if (message.type == MessageType.presentation) return const PresentationShimmer();
    }
    
    if (message.role == 'model' && (message.text == 'Editing image...' || message.text == 'Generating image...')) {
        return const ImageShimmer();
    }

    if (message.role == 'model' && _isStreaming && index == _messages.length - 1 && message.text.isEmpty) {
      return const ThinkingIndicator();
    }

    return DefaultTextStyle(
      style: kMessageTextStyle,
      child: (message.role == 'model' && _isStreaming && index == _messages.length - 1)
          ? StreamingMessageWidget(rawText: message.text, hasAttachment: (index > 0 && (_messages[index - 1].attachedFileName != null || _messages[index - 1].imageBytes != null)))
          : StatelessMessageWidget(
              message: message,
              index: index,
              totalMessageCount: totalMessageCount,
              onRegenerate: () => _regenerateResponse(index - 1),
              onCopy: (text) => _copyToClipboard(text),
              onShowUserOptions: () => _showUserMessageOptions(context, message, index),
            ),
    );
  }

  Widget _buildAttachmentPreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5))
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_attachedImage!.path), height: 120, width: 120, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _attachedImage = null),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForMode(ChatMode mode) {
    switch (mode) {
      case ChatMode.chat: return CupertinoIcons.chat_bubble_2_fill;
      case ChatMode.agent: return CupertinoIcons.sparkles;
      case ChatMode.auto: return Icons.auto_awesome_rounded;
    }
  }

  String _getLabelForMode(ChatMode mode) {
    switch (mode) {
      case ChatMode.chat: return "Chat";
      case ChatMode.agent: return "Agent";
      case ChatMode.auto: return "Auto";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
    final bool canInteract = !_isStreaming && !_isSending;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        systemOverlayStyle: style,
        title: Text(_chatTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          StaticGradientBackground(isDark: isDark),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: AnimatedList(key: _listKey, controller: _scrollController, padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), initialItemCount: _messages.length, itemBuilder: (context, index, animation) { return _buildAnimatedItem(_messages[index], index, animation, _messages.length); },),
                ),
                if (_isProcessingFile)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: FileUploadIndicator(),
                  ),
                if (_attachment != null) AttachmentPreview(attachment: _attachment!, onClear: () => setState(() => _attachment = null)),
                if (_attachedImage != null) _buildAttachmentPreview(),
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, left: 16, right: 16, top: 8),
                  child: GlassmorphismPanel(
                    borderRadius: BorderRadius.circular(28),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(CupertinoIcons.add),
                            onPressed: canInteract ? _showToolsBottomSheet : null,
                            tooltip: 'Attach',
                            color: theme.colorScheme.secondary,
                          ),
                          _buildModeSwitcher(canInteract, theme),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: TextField(
                                controller: _controller,
                                enabled: canInteract,
                                onSubmitted: (val) => _sendMessage(val),
                                textInputAction: TextInputAction.send,
                                maxLines: 5,
                                minLines: 1,
                                decoration: InputDecoration.collapsed(
                                  hintText: !canInteract ? 'Aham is responding...' : 'Ask anything...',
                                  hintStyle: TextStyle(color: theme.hintColor.withOpacity(0.7)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildRightActionButton(canInteract, theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showScrollButton) Positioned(bottom: 110, right: 20, child: AnimatedOpacity(opacity: _showScrollButton ? 1.0 : 0.0, duration: const Duration(milliseconds: 300), child: FloatingActionButton.small(onPressed: _forceScrollToBottom, backgroundColor: isLightTheme(context) ? Colors.black.withOpacity(0.7) : draculaCurrentLine, child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),),),),
        ],
      ),
    );
  }

  Widget _buildRightActionButton(bool canInteract, ThemeData theme) {
    if (_isStreaming || _isSending) {
      return IconButton(
        icon: const Icon(CupertinoIcons.stop_fill),
        onPressed: _stopStreaming,
        tooltip: 'Stop response',
        color: Colors.redAccent.withOpacity(0.9),
      );
    }
    
    if (_controller.text.trim().isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.arrow_upward_rounded),
        onPressed: canInteract ? () => _sendMessage(_controller.text) : null,
        color: theme.colorScheme.primary,
      );
    } else {
      return IconButton(
        icon: const Icon(CupertinoIcons.mic),
        onPressed: canInteract ? () {
          _showStyledSnackBar(message: "Voice input is not implemented yet.");
        } : null,
        tooltip: "Voice input",
        color: theme.colorScheme.secondary,
      );
    }
  }

  Widget _buildModeSwitcher(bool canInteract, ThemeData theme) {
    return PopupMenuButton<ChatMode>(
      onSelected: (mode) {
        if (canInteract) setState(() => _chatMode = mode);
      },
      tooltip: "Select Mode (${_getLabelForMode(_chatMode)})",
      offset: const Offset(0, -150),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      color: theme.brightness == Brightness.dark 
          ? const Color(0xFF2c2c2e).withOpacity(0.8) // Dark mode glass color
          : Colors.white.withOpacity(0.8), // Light mode glass color
      elevation: 8,
      itemBuilder: (context) => ChatMode.values.map((mode) => PopupMenuItem(
        value: mode,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Row(children: [
              Icon(_getIconForMode(mode), size: 20, color: theme.colorScheme.onSurface),
              const SizedBox(width: 12),
              Text(_getLabelForMode(mode)),
            ]),
          ),
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIconForMode(_chatMode),
              size: 18,
              color: canInteract ? theme.colorScheme.secondary : theme.disabledColor,
            ),
            const SizedBox(width: 6),
            Text(
              _getLabelForMode(_chatMode),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: canInteract ? theme.colorScheme.onSurface : theme.disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgentStatusMessage extends StatelessWidget {
  final ChatMessage message;
  const AgentStatusMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = message.statusIcon ?? Icons.info_outline;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}