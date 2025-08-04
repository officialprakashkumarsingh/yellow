import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ahamai/chat_history_service.dart';
import 'package:ahamai/logincredits.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- THIS IS THE FIX
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'chat_screen.dart';
import 'chat_history_service.dart';
import 'models.dart';
import 'notification_screen.dart';
import 'notification_service.dart';
import 'theme.dart';
import 'ui_widgets.dart';
import 'logincredits.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const AhamRoot(),
    ),
  );
}

class AhamRoot extends StatelessWidget {
  const AhamRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, theme, child) {
        // Get the actual current brightness from the context
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final statusBarBrightness = isDarkMode ? Brightness.light : Brightness.dark;
        final navBarColor = isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;
        
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarBrightness,
          systemNavigationBarColor: navBarColor,
          systemNavigationBarIconBrightness: statusBarBrightness,
          systemNavigationBarDividerColor: Colors.transparent,
        ));

        return MaterialApp(
          title: 'AhamAI',
          debugShowCheckedModeBanner: false,
          theme: ThemeNotifier.lightTheme,
          darkTheme: ThemeNotifier.darkTheme,
          themeMode: theme.themeMode,
          home: const AppInitializer(),
        );
      },
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});
  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
          _initializationFuture = Future.wait([
        AuthService.instance.initialize(),
      ApiConfigService.instance.initialize(),
      MobileAds.instance.initialize(),
    ]);
  }

  void _retry() {
    setState(() {
       _initializationFuture = Future.wait([
        AuthService.instance.initialize(),
        ApiConfigService.instance.initialize(),
        MobileAds.instance.initialize(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ThemedLoadingScreen();
        } else if (snapshot.hasError) {
          return ErrorScreen(onRetry: _retry); 
        } else {
          return const AuthGate();
        }
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session != null) {
          return const _AppStartDecision();
                  } else {
            return const AuthScreen();
          }
      },
    );
  }
}

class _AppStartDecision extends StatelessWidget {
  const _AppStartDecision();

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}


class ThemedLoadingScreen extends StatelessWidget {
  const ThemedLoadingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        body: Stack(
          children: [
            StaticGradientBackground(isDark: isDark),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CupertinoActivityIndicator(radius: 15.0),
                  const SizedBox(height: 20),
                  Text('Waking up AhamAI...', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const ErrorScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        body: Stack(
          children: [
            StaticGradientBackground(isDark: isDark),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: GlassmorphismPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 60, color: isDark ? Colors.white70 : Colors.black54),
                        const SizedBox(height: 24),
                        Text("Something Went Wrong", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 12),
                        Text("We couldn't initialize the app services. Please check your internet connection and try again.", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<ChatInfo> _chats = [];
  bool _isLoading = true; // Start with loading true
  late AnimationController _animationController;
  final _chatInfoStream = StreamController<ChatInfo>.broadcast();
  StreamSubscription<ChatInfo>? _chatInfoSubscription;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _notificationTimer;
  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadChatsFromSupabase(); // Load from Supabase on init
    _animationController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..repeat(reverse: true);
    _searchController.addListener(() => setState(() {}));
    
    _chatInfoSubscription = _chatInfoStream.stream.listen((chatInfo) async {
      // This is the listener for when a chat is updated from ChatScreen
      await ChatHistoryService.saveChat(chatInfo);
      
      setState(() {
        final index = _chats.indexWhere((c) => c.id == chatInfo.id);
        if (index != -1) {
          _chats[index] = chatInfo;
        } else {
          _chats.insert(0, chatInfo);
        }
        _sortChats();
      });
    });

    _checkNotifications();
    _notificationTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkNotifications();
    });
  }
  
  void _sortChats() {
    _chats.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final aDate = a.messages.isNotEmpty ? a.messages.last.timestamp : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.messages.isNotEmpty ? b.messages.last.timestamp : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  }

  void _showStyledSnackBar({required String message, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
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

  Future<void> _checkNotifications() async {
    final notifications = await NotificationService.fetchNotifications();
    if (mounted) {
      final hasUnread = NotificationService.hasUnread(notifications);
      if (hasUnread != _hasUnreadNotifications) setState(() => _hasUnreadNotifications = hasUnread);
    }
  }

  Future<void> _loadChatsFromSupabase() async {
    setState(() => _isLoading = true);
    final loadedChats = await ChatHistoryService.getChats();
    if (mounted) {
      setState(() {
        _chats = loadedChats;
        _isLoading = false;
      });
    }
  }

  Future<void> _backupChats() async {
    Navigator.pop(context);
    if (_chats.isEmpty) {
      _showStyledSnackBar(message: 'No chats to back up.', isError: true);
      return;
    }
    try {
      final chatData = jsonEncode(_chats.map((e) => e.toJson()).toList());
      final Uint8List bytes = utf8.encode(chatData);
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
                        fileName: 'ahamai_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        bytes: bytes,
      );
      if (outputFile != null) {
        _showStyledSnackBar(message: 'Backup saved successfully!');
      } else {
        _showStyledSnackBar(message: 'Backup cancelled.');
      }
    } catch (e) {
      _showStyledSnackBar(message: 'Backup failed: $e', isError: true);
    }
  }

  Future<void> _restoreChats() async {
    Navigator.pop(context);
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => StyledDialog(
        title: 'Restore Chats?',
        content: 'This will replace all current chats with the content from the backup file. This action cannot be undone.',
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final backupData = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(backupData);
        final restoredChats = decoded.map((e) => ChatInfo.fromJson(e)).toList();
        
        // Clear old chats from Supabase first
        await Future.wait(_chats.map((c) => ChatHistoryService.deleteChat(c.id)));
        
        // Save new chats to Supabase
        await Future.wait(restoredChats.map((c) => ChatHistoryService.saveChat(c)));

        // Update UI
        setState(() => _chats = restoredChats);
        _sortChats();
        
        if (mounted) _showStyledSnackBar(message: 'Chats restored successfully!');
      } else {
        _showStyledSnackBar(message: 'Restore cancelled.');
      }
    } catch (e) {
      if (mounted) _showStyledSnackBar(message: 'Restore failed: Invalid or corrupted backup file.', isError: true);
    }
  }

  Future<void> _clearAllChats() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => StyledDialog(
        title: 'Clear All Chats?',
        content: 'This will permanently delete all your chat conversations. This action cannot be undone.',
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Create a copy of IDs before clearing, to avoid race conditions
      final chatIdsToDelete = _chats.map((c) => c.id).toList();

      // Clear UI immediately for responsiveness
      setState(() => _chats.clear());

      // Delete all chats from Supabase in the background
      await Future.wait(chatIdsToDelete.map((id) => ChatHistoryService.deleteChat(id)));
      
      if (mounted) {
        Navigator.pop(context);
        _showStyledSnackBar(message: 'All chats have been cleared.');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _chatInfoSubscription?.cancel();
    _chatInfoStream.close();
    _searchController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) => ProfileSettingsSheet(
                scrollController: scrollController,
                onClearAllChats: _clearAllChats,
                onBackupChats: _backupChats,
                onRestoreChats: _restoreChats,
                onSignOut: () async {
                  Navigator.pop(context);
                  await AuthService.instance.signOut();
                  // No need to clear chats locally, AuthGate will rebuild the screen.
                },
              ),
            )).then((_) => setState(() {}));
  }

  void _showRenameDialog(ChatInfo chat, int index) {
    final TextEditingController renameController = TextEditingController(text: chat.title);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) {
        return StyledDialog(
          title: 'Rename Chat',
          contentWidget: TextField(
              controller: renameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter new chat title'),
              onSubmitted: (newTitle) async {
                if (newTitle.trim().isNotEmpty) {
                  Navigator.of(context).pop();
                  final updatedChat = chat.copyWith(title: newTitle.trim());
                  await ChatHistoryService.saveChat(updatedChat);
                  setState(() => _chats[index] = updatedChat);
                }
              }),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () async {
                  final newTitle = renameController.text.trim();
                  if (newTitle.isNotEmpty) {
                    Navigator.of(context).pop();
                    final updatedChat = chat.copyWith(title: newTitle);
                    await ChatHistoryService.saveChat(updatedChat);
                    setState(() => _chats[index] = updatedChat);
                  }
                },
                child: const Text('Rename')),
          ],
        );
      },
    );
  }

  void _showRenameCategoryDialog(ChatInfo chat, int index) {
    final TextEditingController categoryController = TextEditingController(text: chat.category);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) {
        return StyledDialog(
          title: 'Rename Category',
          contentWidget: TextField(
              controller: categoryController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter new category'),
              onSubmitted: (newCategory) async {
                if (newCategory.trim().isNotEmpty) {
                  Navigator.of(context).pop();
                  final updatedChat = chat.copyWith(category: newCategory.trim());
                  await ChatHistoryService.saveChat(updatedChat);
                  setState(() => _chats[index] = updatedChat);
                }
              }),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () async {
                  final newCategory = categoryController.text.trim();
                  if (newCategory.isNotEmpty) {
                    Navigator.of(context).pop();
                    final updatedChat = chat.copyWith(category: newCategory);
                    await ChatHistoryService.saveChat(updatedChat);
                    setState(() => _chats[index] = updatedChat);
                  }
                },
                child: const Text('Rename')),
          ],
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
    final isChatList = _chats.isNotEmpty || _isSearching;

    if (_isSearching) {
      return AppBar(
        systemOverlayStyle: style,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => setState(() { _isSearching = false; _searchController.clear(); })),
        title: TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: 'Search chats...', border: InputBorder.none), style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 18)),
        actions: [if (_searchController.text.isNotEmpty) IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _searchController.clear())],
      );
    } else {
      return AppBar(
        systemOverlayStyle: style,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.person_outline_rounded), onPressed: () => _showProfileSheet(context), tooltip: 'Profile & Settings'),
                  title: const Text('AhamAI'),
        centerTitle: true,
        actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: Badge(isLabelVisible: _hasUnreadNotifications, child: const Icon(Icons.notifications_none_rounded)),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationScreen())).then((_) => _checkNotifications());
              },
            ),
            IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _isSearching = true)),
            const SizedBox(width: 4)
        ],
      );
    }
  }

  Widget _buildEmptyState() {
    final List<Map<String, String>> promptChips = [
      {'icon': '🤔', 'text': 'Explain quantum computing'},
      {'icon': '✍️', 'text': 'Write a short story'},
      {'icon': '🗺️', 'text': 'Plan a 3-day trip to Tokyo'},
      {'icon': '💻', 'text': 'Create a Python script'},
    ];

    void startChatWithPrompt(String prompt) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            initialMessage: prompt,
            chatInfoStream: _chatInfoStream,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
      children: [
        const Text(
                      'Hello, I am AhamAI.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'What can I help you with today?',
          style: TextStyle(fontSize: 20, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: promptChips.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final chip = promptChips[index];
              return PromptChip(
                icon: chip['icon']!,
                text: chip['text']!,
                onTap: () => startChatWithPrompt(chip['text']!),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Explore Core Features',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        FeatureShowcaseCard(
          icon: Icons.auto_awesome_outlined,
          title: 'Autonomous Web Agent',
          description: 'Give me a goal, and I’ll use a browser to achieve it. From scraping data to filling forms.',
          color: const Color(0xFF5E81AC),
          onTap: () => startChatWithPrompt('Scrape the headlines from theverge.com'),
        ),
        const SizedBox(height: 12),
        FeatureShowcaseCard(
          icon: Icons.document_scanner_outlined,
          title: 'Analyze Documents & Images',
          description: 'Upload PDFs, text files, or images and ask me anything about their content.',
          color: const Color(0xFFA3BE8C),
          onTap: () => startChatWithPrompt('Tell me what this document is about.'),
        ),
        const SizedBox(height: 12),
        FeatureShowcaseCard(
          icon: Icons.palette_outlined,
          title: 'Creative Content Generation',
          description: 'Generate complete slide presentations, images, and diagrams from a simple text prompt.',
          color: const Color(0xFFB48EAD),
          onTap: () => startChatWithPrompt('Create a 5-slide presentation on the history of AI'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentChatList = _isSearching ? _chats.where((chat) => chat.title.toLowerCase().contains(_searchController.text.toLowerCase()) || chat.messages.any((message) => message.text.toLowerCase().contains(_searchController.text.toLowerCase()))).toList() : _chats;

    final groupedList = _groupChatsByDate(currentChatList);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          StaticGradientBackground(isDark: isDark),
          SafeArea(
            bottom: false,
            child: _isLoading 
              ? const Center(child: CupertinoActivityIndicator())
              : _chats.isEmpty && !_isSearching
                ? _buildEmptyState()
                : ListView.builder(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: groupedList.length,
                    itemBuilder: (context, index) {
                      final item = groupedList[index];
                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 16, left: 8),
                          child: Text(item, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        );
                      } else if (item is ChatInfo) {
                        return ChatListItem(
                          chat: item,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(chatTitle: item.title, initialMessages: item.messages, chatId: item.id, isPinned: item.isPinned, isGenerating: item.isGenerating, isStopped: item.isStopped, chatInfoStream: _chatInfoStream, category: item.category))),
                          onLongPress: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => GlassmorphismPanel(
                              isBottomSheet: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                        leading: const Icon(Icons.push_pin_outlined),
                                        title: Text(item.isPinned ? 'Unpin Chat' : 'Pin Chat'),
                                        onTap: () async {
                                          Navigator.pop(context);
                                          final updatedChat = item.copyWith(isPinned: !item.isPinned);
                                          await ChatHistoryService.saveChat(updatedChat);
                                          setState(() {
                                            final chatIndex = _chats.indexWhere((c) => c.id == item.id);
                                            if (chatIndex != -1) _chats[chatIndex] = updatedChat;
                                            _sortChats();
                                          });
                                        }),
                                    ListTile(
                                        leading: const Icon(Icons.drive_file_rename_outline),
                                        title: const Text('Rename Chat'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          final originalIndex = _chats.indexWhere((c) => c.id == item.id);
                                          if (originalIndex != -1) {
                                            _showRenameDialog(item, originalIndex);
                                          }
                                        }),
                                    ListTile(
                                        leading: const Icon(Icons.category_outlined),
                                        title: const Text('Rename Category'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          final originalIndex = _chats.indexWhere((c) => c.id == item.id);
                                          if (originalIndex != -1) {
                                            _showRenameCategoryDialog(item, originalIndex);
                                          }
                                        }),
                                    ListTile(
                                        leading: const Icon(Icons.delete_outline),
                                        title: const Text('Delete Chat'),
                                        onTap: () async {
                                          Navigator.pop(context);
                                          await ChatHistoryService.deleteChat(item.id);
                                          setState(() => _chats.removeWhere((c) => c.id == item.id));
                                        }),
                                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(chatInfoStream: _chatInfoStream))).then((_) => setState((){})),
              backgroundColor: Colors.transparent,
              elevation: 0,
              hoverElevation: 0,
              focusElevation: 0,
              highlightElevation: 0,
              child: GlassmorphismPanel(
                borderRadius: BorderRadius.circular(16),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.add_rounded),
                ),
              ),
            ),
    );
  }

  String _getDateCategory(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
    
    final aDate = DateTime(date.year, date.month, date.day);

    if (aDate == today) return 'Today';
    if (aDate == yesterday) return 'Yesterday';
    if (aDate.isAfter(startOfWeek.subtract(const Duration(days: 1)))) return 'This Week';
    if (aDate.month == now.month && aDate.year == now.year) return 'This Month';
    
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${monthNames[date.month - 1]} ${date.year}';
  }

  List<dynamic> _groupChatsByDate(List<ChatInfo> chats) {
    if (chats.isEmpty) return [];

    final List<dynamic> groupedItems = [];
    String? lastHeader;

    final pinnedChats = chats.where((c) => c.isPinned).toList();
    final unpinnedChats = chats.where((c) => !c.isPinned).toList();
    
    if (pinnedChats.isNotEmpty) {
      groupedItems.add('Pinned');
      groupedItems.addAll(pinnedChats);
    }

    for (var chat in unpinnedChats) {
      final date = chat.messages.isNotEmpty ? chat.messages.last.timestamp : DateTime.now();
      final categoryHeader = _getDateCategory(date);

      if (categoryHeader != lastHeader) {
        groupedItems.add(categoryHeader);
        lastHeader = categoryHeader;
      }
      groupedItems.add(chat);
    }
    return groupedItems;
  }
}

class PromptChip extends StatelessWidget {
  final String icon;
  final String text;
  final VoidCallback onTap;

  const PromptChip({super.key, required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: GlassmorphismPanel(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(text),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureShowcaseCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const FeatureShowcaseCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphismPanel(
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Theme.of(context).hintColor),
            ],
          ),
        ),
      ),
    );
  }
}


class ProfileSettingsSheet extends StatefulWidget {
  final VoidCallback onClearAllChats;
  final VoidCallback onBackupChats;
  final VoidCallback onRestoreChats;
  final VoidCallback onSignOut;
  final ScrollController scrollController;

  const ProfileSettingsSheet({super.key, required this.onClearAllChats, required this.onBackupChats, required this.onRestoreChats, required this.scrollController, required this.onSignOut});

  @override
  State<ProfileSettingsSheet> createState() => _ProfileSettingsSheetState();
}

class _ProfileSettingsSheetState extends State<ProfileSettingsSheet> {
  late String _selectedChatModelId;
  List<ChatModelConfig> _chatModels = [];

  @override
  void initState() {
    super.initState();
    _chatModels = ApiConfigService.instance.chatModels;
    _selectedChatModelId = ApiConfigService.instance.defaultModelId;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedChatModelId = prefs.getString('chat_model') ?? ApiConfigService.instance.defaultModelId;
      });
    }
  }

  Future<void> _saveChatModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_model', modelId);
    setState(() => _selectedChatModelId = modelId);
  }

  @override
  Widget build(BuildContext context) {
    return GlassmorphismPanel(
      isBottomSheet: true,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Profile & Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
          ),
          // REMOVED: The manual theme switch is no longer needed.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Account', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(AuthService.instance.currentUser?.email ?? 'Not available'),
          ),
          RewardedAdTile(onAdWatched: () => setState(() {})),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Data Control', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Backup Chats'),
            subtitle: const Text('Save chats to a file.'),
            onTap: widget.onBackupChats,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Restore Chats'),
            subtitle: const Text('Restore chats from a file.'),
            onTap: widget.onRestoreChats,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade400),
            title: Text('Clear All Chats', style: TextStyle(color: Colors.red.shade400)),
            onTap: widget.onClearAllChats,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Chat AI Model', style: Theme.of(context).textTheme.titleMedium),
          ),
          ..._chatModels.map((model) {
            final isDown = model.status == 'down';
            final subtitleText = isDown ? '${model.description} (Down)' : model.description;
            return RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(model.displayName, style: isDown ? TextStyle(color: Theme.of(context).disabledColor) : null),
              subtitle: Text(subtitleText, style: isDown ? const TextStyle(color: Colors.red) : null),
              value: model.modelId,
              groupValue: _selectedChatModelId,
              onChanged: isDown ? null : (val) => _saveChatModel(val!),
            );
          }),
          const Divider(),
           ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: Colors.red.shade400),
            title: Text('Sign Out', style: TextStyle(color: Colors.red.shade400)),
            onTap: widget.onSignOut,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }
}