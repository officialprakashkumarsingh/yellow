import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:ahamai/openai_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:ahamai/api.dart';
import 'package:ahamai/chat_ui_helpers.dart';
import 'package:ahamai/file_processing.dart';
import 'package:ahamai/image_editor.dart';
import 'package:ahamai/logincredits.dart';
import 'package:ahamai/models.dart';
import 'package:ahamai/theme.dart';
import 'package:ahamai/ui_widgets.dart';
import 'package:ahamai/web_search.dart';
import 'package:ahamai/chat_mode_logic.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kMessageTextStyle = TextStyle(fontSize: 15.5, height: 1.45);

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
  
  late String _selectedChatModelId;
  bool _isModelSetupComplete = false;
  
  // Speech-to-text functionality
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  StreamSubscription? _streamSubscription;
  http.Client? _httpClient;

  List<SearchResult>? _lastSearchResults;
  bool _showScrollButton = false;
  bool _isProcessingFile = false;
  XFile? _attachedImage;
  dynamic _attachment;

  late String _chatId;
  late String _chatTitle;
  late String _category;
  late bool _isPinned;

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
    _initSpeech();
    
    _controller.addListener(() {
      setState(() {});
    });

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100;
        if (_showScrollButton && isAtBottom) {
          setState(() => _showScrollButton = false);
        } else if (!_showScrollButton && !isAtBottom && _scrollController.position.pixels > 200) {
          setState(() => _showScrollButton = true);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      final hasContent = _messages.any((msg) => msg.role == 'user' && msg.text.trim().isNotEmpty);
      if (hasContent) {
        _addMessageToList(ChatMessage(
          role: 'system',
          text: '[Chat saved automatically]',
          timestamp: DateTime.now(),
        ));
      }
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

    if (mounted) setState(() {});
  }

  // Initialize speech-to-text
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  // Start listening for speech
  void _startListening() async {
    if (!_speechEnabled) {
      _showStyledSnackBar(message: "Speech recognition not available", isError: true);
      return;
    }

    setState(() => _isListening = true);
    
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
        
        // Auto-send when speech is final (user finished speaking)
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _controller.text.trim().isNotEmpty) {
              _sendMessage(_controller.text);
            }
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2), // Reduced to 2 seconds for faster response
      partialResults: true,
      localeId: 'en_US',
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  // Stop listening for speech
  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
    
    // Auto-send if there's text when manually stopped
    if (_controller.text.trim().isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _controller.text.trim().isNotEmpty) {
          _sendMessage(_controller.text);
        }
      });
    }
  }

  // Toggle listening
  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _addMessageToList(ChatMessage message) {
    if (!mounted) return;

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
    
    // Credit system removed - no longer needed

    final modelConfig = ApiConfigService.instance.getModelConfigById(_selectedChatModelId);
        if (_attachedImage != null) {
      _httpClient?.close();
      await _sendVisionMessage(input, _attachedImage!);
    } else {
      await _sendTextMessage(input);
    }
  }

  void _handleStreamChunk(String textChunk) {
    if (_isStoppedByUser) {
      _streamSubscription?.cancel();
      return;
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
    final userMessage = ChatMessage(role: 'user', text: input, timestamp: DateTime.now(), imageBytes: await imageFile.readAsBytes());
    _addMessageToList(userMessage);
    setState(() { _isStreaming = true; _attachedImage = null; });

    final List<ChatMessage> historyForAI = _messages.where((msg) => msg.role != 'system').take(_messages.length - 1).toList();

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

         _addMessageToList(ChatMessage(role: 'model', text: '', imageBytes: await imageFile.readAsBytes(), timestamp: DateTime.now()));

    try {
      final modeResult = await ChatModeHandler(prompt: finalInputForAI, mode: ChatMode.auto).process();
      
      final responseStream = await OpenAIService.instance.streamChatCompletion(
        prompt: finalInputForAI,
        messages: historyForAI,
        systemPrompt: modeResult.systemPrompt,
                 imageBytes: await imageFile.readAsBytes(),
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

    _addMessageToList(ChatMessage(role: 'user', text: input, timestamp: DateTime.now(), attachedFileName: _attachment?.fileName, imageBytes: _attachedImage != null ? await _attachedImage!.readAsBytes() : null));

    _controller.clear();
    setState(() {
      _isStreaming = true;
      _attachment = null;
      _attachedImage = null;
    });

         _addMessageToList(ChatMessage(role: 'model', text: '', timestamp: DateTime.now()));

    try {
      final modeResult = await ChatModeHandler(prompt: finalInputForAI, mode: ChatMode.auto).process();
      
      final responseStream = await OpenAIService.instance.streamChatCompletion(
        prompt: finalInputForAI,
        messages: _messages.where((msg) => msg.role != 'system').take(_messages.length - 2).toList(), // Exclude the last two messages (user and empty assistant)
        systemPrompt: modeResult.systemPrompt,
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
      print("AhamAI Streaming Error: $error");
      if (_messages.isNotEmpty && _messages.last.role == 'model') {
        final errorMessage = error is http.ClientException
            ? 'ERROR: ${error.message}'
            : 'ERROR: $error';
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
       return;
    }

    final lastMessageText = _messages.last.text.trim();
    final lastUserMessage = _messages.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage(role: 'user', text: '', timestamp: DateTime.now()));

         if (!mounted) {
       _httpClient?.close();
       return;
     }

    _httpClient?.close();
    _httpClient = null;

    if (lastMessageText.isEmpty) {
      _removeMessagesFrom(_messages.length - 1);
      
      final lastMessage = _messages.last;
      final finalMessage = ChatMessage(
        role: lastMessage.role,
        text: "I apologize, but I couldn't generate a response. Please try again.",
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
  }

  void _smoothScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100;
        if (isAtBottom) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
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
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
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
    
    _removeMessagesFrom(userMessageIndex + 1);
    
    setState(() => _isSending = true);
    
    try {
      if (userMessage.imageBytes != null) {
        final messageImageBytes = userMessage.imageBytes!;
        final messageText = userMessage.text;
        _attachedImage = XFile.fromData(messageImageBytes, name: 'image.jpg');
        
        await _sendMessage(messageText);
      } else {
        if(mounted) {
            setState(() => _isSending = false);
        }
      }
    } catch (e) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit and Resend'), onTap: () { Navigator.pop(context); setState(() { _controller.text = message.text; _removeMessagesFrom(index); _stopStreaming(); }); }),
            ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Copy'), onTap: () { Navigator.pop(context); _copyToClipboard(message.text); }),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  void _pickImage(ImageSource source) async {
    Navigator.pop(context);
    try {
      setState(() {
        _isProcessingFile = true;
        _attachedImage = null;
        _attachment = null;
      });
      final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 70);
      setState(() {
        _isProcessingFile = false;
        _attachedImage = image;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingFile = false);
      }
    }
  }

  void _pickAndProcessFile() async {
    Navigator.pop(context);
    setState(() => _isProcessingFile = true);
    try {
      final attachment = await FileProcessingService.pickAndProcessFile();
      if (mounted) {
        setState(() {
          _attachment = attachment;
          _attachedImage = null;
          _isProcessingFile = false;
        });
      }
    } catch (e) {
      setState(() => _isProcessingFile = false);
    }
    
    if (mounted) {
      setState(() => _isProcessingFile = false);
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
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  FileSourceButton(icon: CupertinoIcons.camera, label: 'Camera', onTap: () => _pickImage(ImageSource.camera)), 
                  FileSourceButton(icon: CupertinoIcons.photo, label: 'Photos', onTap: () => _pickImage(ImageSource.gallery)), 
                  FileSourceButton(icon: CupertinoIcons.folder, label: 'Files', onTap: _pickAndProcessFile)
                ]),
                SizedBox(height: MediaQuery.of(context).padding.bottom)
              ]
            )
          )
        ),
      )
    );
  }

  Widget _buildAnimatedItem(ChatMessage message, int index, Animation<double> animation, int totalMessageCount, {bool isRemoving = false}) {
    return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: isRemoving ? Curves.easeOut : Curves.easeIn), child: _buildMessage(message, index, totalMessageCount),);
  }

  Widget _buildMessage(ChatMessage message, int index, int totalMessageCount) {
    if (message.role == 'system') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5))
              ),
              child: Text(message.text, style: kMessageTextStyle.copyWith(color: message.text.startsWith('❌') ? Colors.redAccent : Theme.of(context).colorScheme.onSurface)),
            ),
          ],
        ),
      );
    }

    if (message.role == 'model' && message.text.isEmpty && index == _messages.length -1) {
        if (message.type == MessageType.image) return const ImageShimmer();
        if (message.type == MessageType.presentation) return const PresentationShimmer();
    }
    
    if (message.role == 'model' && (message.text == 'Editing image...' || message.text == 'Generating image...')) {
        return const ImageShimmer();
    }

    // Show thinking indicator only when streaming AND message is completely empty
    if (message.role == 'model' && _isStreaming && index == _messages.length - 1 && message.text.isEmpty) {
      return const ThinkingIndicator();
    }

    return DefaultTextStyle(
      style: kMessageTextStyle,
      child: (message.role == 'model' && _isStreaming && index == _messages.length - 1 && message.text.isNotEmpty)
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
    if (_attachedImage == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(File(_attachedImage!.path), height: 120, width: 120, fit: BoxFit.cover),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _attachedImage = null),
                  child: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canInteract = !_isStreaming && !_isSending;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_chatTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: theme.brightness == Brightness.dark 
                ? [draculaBackground.withOpacity(0.95), draculaCurrentLine.withOpacity(0.95)]
                : [Colors.white.withOpacity(0.95), Colors.grey.shade50.withOpacity(0.95)],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          StaticGradientBackground(isDark: theme.brightness == Brightness.dark, child: const SizedBox.expand()),
          Column(
            children: [
              Expanded(
                child: AnimatedList(key: _listKey, controller: _scrollController, padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), initialItemCount: _messages.length, itemBuilder: (context, index, animation) { return _buildAnimatedItem(_messages[index], index, animation, _messages.length); },),
              ),
              Column(
                children: [
                if (_isProcessingFile)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                if (_attachment != null) AttachmentPreview(attachment: _attachment, onClear: () => setState(() => _attachment = null)),
                if (_attachedImage != null) _buildAttachmentPreview(),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: theme.brightness == Brightness.dark 
                        ? [Colors.transparent, draculaBackground.withOpacity(0.8)]
                        : [Colors.transparent, Colors.white.withOpacity(0.8)],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: IconButton(
                          icon: const Icon(CupertinoIcons.add),
                          onPressed: canInteract ? _showToolsBottomSheet : null,
                          tooltip: 'Attach',
                          color: theme.colorScheme.secondary,
                          iconSize: 24,
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: TextField(
                            controller: _controller,
                            enabled: canInteract,
                            onSubmitted: (val) => _sendMessage(val),
                            textInputAction: TextInputAction.send,
                            maxLines: 5,
                            minLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: !canInteract ? 'AhamAI is responding...' : 'Ask anything...',
                              hintStyle: TextStyle(
                                color: theme.hintColor.withOpacity(0.7),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: _buildRightActionButton(canInteract, theme),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_showScrollButton) Positioned(bottom: 110, right: 20, child: AnimatedOpacity(opacity: _showScrollButton ? 1.0 : 0.0, duration: const Duration(milliseconds: 300), child: FloatingActionButton.small(onPressed: _forceScrollToBottom, backgroundColor: isLightTheme(context) ? Colors.black.withOpacity(0.7) : draculaCurrentLine, child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),),),),
        ],
      ),
    );
  }

  Widget _buildRightActionButton(bool canInteract, ThemeData theme) {
    if (_isStreaming || _isSending) {
      return IconButton(
        icon: const Icon(Icons.stop_circle_outlined),
        onPressed: _stopStreaming,
        color: Colors.red,
        tooltip: 'Stop',
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
        icon: Icon(
          _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
          color: _isListening ? Colors.red : null,
        ),
        onPressed: canInteract && _speechEnabled ? _toggleListening : null,
        tooltip: _isListening ? "Stop recording" : "Voice input",
        color: _isListening ? Colors.red : theme.colorScheme.secondary,
      );
    }
  }

  // Mode switcher removed - AI auto-detects the appropriate mode
}