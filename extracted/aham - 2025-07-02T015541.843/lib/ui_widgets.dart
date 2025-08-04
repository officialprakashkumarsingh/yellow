import 'dart:async';
import 'dart:ui';
import 'package:aham/models.dart';
import 'package:aham/presentation_generator.dart';
import 'package:aham/theme.dart';
import 'package:aham/web_search.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'chat_screen.dart';
import 'chat_ui_helpers.dart';
import 'live_activity_indicator.dart';

// --- Generic UI Widgets ---
class StyledDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? contentWidget;
  final List<Widget> actions;

  const StyledDialog({super.key, required this.title, this.content, this.contentWidget, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassmorphismPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (content != null) Text(content!),
              if (contentWidget != null) contentWidget!,
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)
            ],
          ),
        ),
      ),
    );
  }
}

class StaticGradientBackground extends StatelessWidget {
  final bool isDark;
  const StaticGradientBackground({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final colors = isDark ? [const Color(0xFF1c1c1e), const Color(0xFF101011)] : [const Color(0xFFf7f7f7), const Color(0xFFFFFFFF)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

class GlassmorphismPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isBottomSheet;
  final BorderRadius? borderRadius;

  const GlassmorphismPanel({super.key, required this.child, this.onTap, this.onLongPress, this.isBottomSheet = false, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.2);
    final effectiveBorderRadius = borderRadius ?? (isBottomSheet ? const BorderRadius.vertical(top: Radius.circular(28)) : BorderRadius.circular(20));

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            splashColor: isDark ? Colors.white12 : Colors.black12,
            highlightColor: isDark ? Colors.white12 : Colors.black12,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: effectiveBorderRadius,
                border: Border.all(color: borderColor, width: 1),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}


// --- Chat Screen Specific Widgets ---

class StreamingMessageWidget extends StatelessWidget {
  final String rawText;
  final bool hasAttachment;
  const StreamingMessageWidget({super.key, required this.rawText, this.hasAttachment = false});

  @override
  Widget build(BuildContext context) {
    final isDark = !isLightTheme(context);

    if (rawText.isEmpty) {
      if (hasAttachment) {
        return const LiveActivityIndicator(
          icon: Icons.document_scanner_outlined,
          initialLabel: "Analyzing...",
          activities: ["Reading content...", "Formulating response..."],
        );
      }
      return const Align(alignment: Alignment.centerLeft, child: GeneratingIndicator());
    }

    final content = _parseMessageContent(rawText);
    final thoughts = content['thoughts']!;
    final cleanedMessage = content['cleanedMessage']!;
    
    final messageContent = MarkdownBody(data: cleanedMessage, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)));

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thoughts.isNotEmpty) ThoughtsExpansionPanel(thoughts: thoughts),
          if (cleanedMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: isDark 
                ? Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent)
                : Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent),
            ),
        ],
      ),
    );
  }
}

class StatelessMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final int index;
  final int totalMessageCount;
  final VoidCallback onRegenerate;
  final Function(String) onCopy;
  final VoidCallback onShowUserOptions;

  const StatelessMessageWidget({super.key, required this.message, required this.index, required this.totalMessageCount, required this.onRegenerate, required this.onCopy, required this.onShowUserOptions});

  @override
  Widget build(BuildContext context) {
    final isDark = !isLightTheme(context);

     switch (message.type) {
      case MessageType.image:
        if (message.imageUrl == null) return const LiveActivityIndicator(initialLabel: 'Creating image...', activities: ['Warming up the pixels...', 'Painting your vision...'], icon: Icons.palette_outlined);
        return Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)), constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(message.imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Icon(Icons.error)))));
      case MessageType.presentation:
        if (message.slides == null) return const LiveActivityIndicator(initialLabel: 'Generating slides...', activities: ['Designing layout...', 'Writing content...', 'Finalizing presentation...'], icon: Icons.slideshow_outlined);
        return Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PresentationViewScreen(slides: message.slides!, topic: message.text.replaceFirst('Presentation ready: ', '')))), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.slideshow, size: 20), const SizedBox(width: 12), Flexible(child: Text(message.text, style: const TextStyle(fontWeight: FontWeight.bold)))]))));
      case MessageType.text:
      default:
        final isModelMessage = message.role == 'model';
        if (isModelMessage) {
          if (message.text == 'Searching the web...') return const LiveActivityIndicator(initialLabel: 'Searching the web...', activities: ['Analyzing top results...', 'Composing answer...'], icon: Icons.public);
          
          final content = _parseMessageContent(message.text);
          final thoughts = content['thoughts']!;
          final cleanedMessage = content['cleanedMessage']!;

          final messageContent = MarkdownBody(data: cleanedMessage, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)));
          final bool isLastMessage = index == totalMessageCount - 1;
          
          return Align(
            alignment: Alignment.centerLeft, 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                if (thoughts.isNotEmpty) ThoughtsExpansionPanel(thoughts: thoughts),
                if (cleanedMessage.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: isDark 
                      ? Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent)
                      : Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent),
                  ),
                if (cleanedMessage.isNotEmpty && !message.text.startsWith('❌ Error:')) 
                  AiMessageActions(onCopy: () => onCopy(cleanedMessage), onRegenerate: isLastMessage ? onRegenerate : null)
              ]
            )
          );
        }
        
        // User Message
        final userMessageBody = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.imageBytes != null) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(message.imageBytes!, height: 150))), 
              if (message.attachedFileName != null) FileAttachmentInMessage(message: message), 
              if (message.text.isNotEmpty) MarkdownBody(
                data: message.text, 
                selectable: false, 
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyLarge?.copyWith(color: isDark ? Colors.white : Colors.black87), 
                  code: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace', 
                    backgroundColor: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.15), 
                    color: isDark ? Colors.white : Colors.black87)
                )
              )
            ]
        );

        return GestureDetector(
          onLongPress: onShowUserOptions, 
          child: Align(
            alignment: Alignment.centerRight, 
            child: isDark
              ? Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), 
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: GlassmorphismPanel(
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: userMessageBody),
                  )
                )
              : Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), 
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), 
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(20)), 
                  child: userMessageBody
                )
            )
        );
    }
  }
}

class AiMessageActions extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;
  
  const AiMessageActions({ super.key, required this.onCopy, this.onRegenerate });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.content_copy_outlined, size: 20),
            tooltip: 'Copy',
            splashRadius: 20,
          ),
          if(onRegenerate != null)
            IconButton(
              onPressed: onRegenerate,
              icon: const Icon(Icons.sync_outlined, size: 20),
              tooltip: 'Regenerate',
              splashRadius: 20,
            ),
        ],
      ),
    );
  }
}

class FileAttachmentInMessage extends StatelessWidget {
  final ChatMessage message;
  const FileAttachmentInMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final hasContainedFiles = message.attachedContainedFiles != null && message.attachedContainedFiles!.isNotEmpty;
    final icon = hasContainedFiles ? Icons.folder_zip_outlined : Icons.description_outlined;
    final isDark = !isLightTheme(context);
    final textColor = isDark ? Colors.white : Colors.black87;
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: textColor.withOpacity(0.8)), const SizedBox(width: 8), Flexible(child: Text(message.attachedFileName!, style: TextStyle(fontWeight: FontWeight.bold, color: textColor), overflow: TextOverflow.ellipsis))]), if (hasContainedFiles) Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(iconColor: textColor.withOpacity(0.8), collapsedIconColor: textColor.withOpacity(0.8), tilePadding: const EdgeInsets.only(left: 28, right: 8), title: Text('${message.attachedContainedFiles!.length} files', style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.9))), children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 120), child: ListView.builder(shrinkWrap: true, itemCount: message.attachedContainedFiles!.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(left: 28, right: 8, top: 2, bottom: 2), child: Text(message.attachedContainedFiles![index], style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8), fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis))))])), if(message.text.isNotEmpty) Container(height: 1, color: textColor.withOpacity(0.2), margin: const EdgeInsets.only(top: 8))]));
  }
}

class ThoughtsExpansionPanel extends StatelessWidget {
  final String thoughts;
  const ThoughtsExpansionPanel({super.key, required this.thoughts});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: GlassmorphismPanel(
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14.0),
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18, color: draculaPurple),
                const SizedBox(width: 8),
                Text('Thoughts', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            subtitle: const Text('Expand to view model thoughts'),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  thoughts.trim(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, String> _parseMessageContent(String rawText) {
  final thoughtRegex = RegExp(r"<(thought|tool_code|think|reasoning)>([\s\S]*?)<\/\1>\n*", multiLine: true);
  final thoughtsBuffer = StringBuffer();
  
  final cleanedText = rawText.replaceAllMapped(thoughtRegex, (match) {
    final thoughtContent = match.group(2)?.trim();
    if (thoughtContent != null && thoughtContent.isNotEmpty) {
      thoughtsBuffer.writeln(thoughtContent);
    }
    return '';
  });
  
  final thoughts = thoughtsBuffer.toString().trim();

  return {
    'thoughts': thoughts,
    'cleanedMessage': cleanedText.trim(),
  };
}


// --- Home Screen Specific Widgets ---

class HomeScreenSearchBar extends StatelessWidget {
  const HomeScreenSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2c2c2e) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const TextField(
        decoration: InputDecoration(
          icon: Icon(Icons.search_rounded),
          border: InputBorder.none,
          hintText: 'Search',
        ),
      ),
    );
  }
}

class CreateNewButton extends StatelessWidget {
  final VoidCallback onPressed;
  const CreateNewButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GlassmorphismPanel(
      onTap: onPressed,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded),
            SizedBox(width: 8),
            Text('Create new Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String prompt;
  final Color color;
  final StreamController<ChatInfo> chatInfoStream;

  const SuggestionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.prompt,
    required this.color,
    required this.chatInfoStream,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(initialMessage: prompt, chatInfoStream: chatInfoStream))),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: isDark
                ? [color.withOpacity(0.15), const Color(0xFF1c1c1e).withOpacity(0.2)]
                : [color.withOpacity(0.2), Colors.white.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade300, width: 1),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 12,
              child: Icon(Icons.north_east_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black54),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 24, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                  const Spacer(),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatListItem extends StatelessWidget {
  final ChatInfo chat;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ChatListItem({super.key, required this.chat, required this.onTap, required this.onLongPress});

  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'coding':
        return Icons.code_rounded;
      case 'web search':
      case 'facts':
        return Icons.search_rounded;
      case 'creative':
        return Icons.brush_rounded;
      case 'science':
        return Icons.science_outlined;
      case 'health':
        return Icons.local_hospital_outlined;
      case 'history':
        return Icons.history_edu_rounded;
      case 'image generation':
        return Icons.image_outlined;
      case 'presentation maker':
        return Icons.slideshow_outlined;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final icon = _getIconForCategory(chat.category);
    final categoryTag = chat.category;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: itemColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: isDark ? Colors.white70 : Colors.black54),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.messages.isEmpty ? 'No messages yet' : chat.messages.last.text,
                    style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#$categoryTag',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (chat.isPinned) Icon(Icons.push_pin_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black54),
          ],
        ),
      ),
    );
  }
}