import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // Added for MarkdownBody

import 'package:ahamai/api.dart';
import 'package:ahamai/theme.dart';
import 'package:ahamai/web_search.dart';
import 'package:ahamai/models.dart'; // For ChatMessage, MessageType
import 'package:ahamai/chat_ui_helpers.dart'; // For ChatInfo
import 'package:ahamai/live_activity_indicator.dart'; // For LiveActivityIndicator
import 'package:ahamai/presentation_generator.dart'; // For PresentationViewScreen

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


// --- Chat Screen Specific Widgets (MOVED HERE) ---

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
      // Changed to use GeneratingIndicator from ui_widgets.dart
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

          return Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (thoughts.isNotEmpty) ThoughtsExpansionPanel(thoughts: thoughts),
            if (cleanedMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: isDark
                ? Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent)
                : Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: messageContent),
              ),
            if (message.searchResults != null && message.searchResults!.isNotEmpty) SearchResultsWidget(results: message.searchResults!),
            if (cleanedMessage.isNotEmpty && !message.text.startsWith('ERROR:')) AiMessageActions(onCopy: () => onCopy(cleanedMessage), onRegenerate: isLastMessage ? onRegenerate : null)
          ]));
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
    // Get theme color for grey icons
    final greyIconColor = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade700 : Colors.grey.shade400;

    return Padding(
      padding: const EdgeInsets.only(left: 12.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Changed Copy Icon to iOS style and Grey ---
          IconButton(
            onPressed: onCopy,
            icon: const Icon(CupertinoIcons.doc_on_doc), // iOS style copy icon
            tooltip: 'Copy',
            splashRadius: 20,
            iconSize: 20,
            color: greyIconColor, // Apply grey color
          ),
          if(onRegenerate != null)
            // --- Changed Regenerate Icon to iOS style and Grey ---
            IconButton(
              onPressed: onRegenerate,
              icon: const Icon(CupertinoIcons.arrow_counterclockwise), // iOS style refresh icon
              tooltip: 'Regenerate',
              splashRadius: 20,
              iconSize: 20,
              color: greyIconColor, // Apply grey color
            ),
        ],
      ),
    );
  }
}

class SearchResultsWidget extends StatelessWidget {
  final List<SearchResult> results;
  const SearchResultsWidget({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 22, top: 8, bottom: 8), child: Text("Sources", style: Theme.of(context).textTheme.titleSmall)), SizedBox(height: 90, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8), itemCount: results.length, itemBuilder: (context, index) => SearchResultCard(result: results[index])))]);
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
        color: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade200,
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
      onTap: () {
        // TODO: Navigate to chat screen - for now just close
        Navigator.pop(context);
      },
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


// --- Other Widgets that might be useful or have been updated ---

// FileSourceButton (from ui_widgets.dart previously)
class FileSourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const FileSourceButton({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Changed File Source Icons to iOS style ---
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// SearchResultCard (from ui_widgets.dart previously)
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({super.key, required this.result});

  final SearchResult result;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
       print('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchUrl(result.url),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (result.faviconUrl != null)
                  Image.network(
                    result.faviconUrl!,
                    height: 16,
                    width: 16,
                    errorBuilder: (_, __, ___) => const Icon(Icons.public, size: 16),
                  )
                else
                  const Icon(Icons.public, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    Uri.parse(result.url).host,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                result.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ImagePromptSheet (from ui_widgets.dart previously)
class ImagePromptSheet extends StatefulWidget {
  final Function(String prompt, String model) onGenerate;
  const ImagePromptSheet({super.key, required this.onGenerate});

  @override
  State<ImagePromptSheet> createState() => _ImagePromptSheetState();
}

class _ImagePromptSheetState extends State<ImagePromptSheet> {
  final _promptController = TextEditingController();
  String? _selectedModel;

  void _submit() {
    if (_promptController.text.trim().isNotEmpty && _selectedModel != null) {
      widget.onGenerate(_promptController.text.trim(), _selectedModel!);
      Navigator.pop(context);
    }
  }

  void _showModelSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return FutureBuilder<List<ImageModelConfig>>(
          future: ImageApi.fetchModels(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(heightFactor: 4, child: CircularProgressIndicator());
            }
            final models = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                return ListTile(
                  title: Text(model.displayName),
                  trailing: _selectedModel == model.modelId ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
                  onTap: () {
                    setState(() => _selectedModel = model.modelId);
                    Navigator.pop(context);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    ImageApi.fetchModels().then((models) {
      if (mounted && models.isNotEmpty) {
        setState(() => _selectedModel = models.first.modelId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Generate Image', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            autofocus: true,
            decoration: InputDecoration(hintText: 'e.g., A fox in a spacesuit', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showModelSelection,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_selectedModel ?? 'Select a model...'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.generating_tokens_outlined),
              label: const Text('Generate'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// GeneratingIndicator (from ui_widgets.dart previously)
class GeneratingIndicator extends StatefulWidget {
  final double size;
  const GeneratingIndicator({super.key, this.size = 12});
  @override
  _GeneratingIndicatorState createState() => _GeneratingIndicatorState();
}

class _GeneratingIndicatorState extends State<GeneratingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 800), vsync: this)..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    // Using a theme color for better integration
    final indicatorColor = Theme.of(context).colorScheme.secondary;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(opacity: _animation.value, child: Icon(Icons.circle, size: widget.size, color: indicatorColor)),
    );
  }
}

// CodeStreamingSheet (from ui_widgets.dart previously)
class CodeStreamingSheet extends StatelessWidget {
  final ValueNotifier<String> notifier;
  const CodeStreamingSheet({super.key, required this.notifier});
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Generated Code', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
              const SizedBox(height: 12),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: notifier,
                  builder: (context, code, _) => SingleChildScrollView(controller: controller, child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final code = notifier.value;
                    if (code.trim().isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copied to clipboard!")));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Code"),
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }
}

/// A custom, package-free shimmer effect widget.
class CustomShimmer extends StatefulWidget {
  final Widget child;
  const CustomShimmer({super.key, required this.child});

  @override
  State<CustomShimmer> createState() => _CustomShimmerState();
}

class _CustomShimmerState extends State<CustomShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = !isLightTheme(context);
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final slide = _controller.value * 2.0 - 1.0; // From -1.0 to 1.0
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: slide),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}


// Shimmer placeholder for image generation with label
class ImageShimmer extends StatelessWidget {
  const ImageShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    // The shader mask needs a solid color to work on.
    // We use black as the 'paint' color, which will be completely replaced by the gradient.
    const shimmerPaintColor = Colors.black;

    return Align(
      alignment: Alignment.centerLeft,
      child: CustomShimmer(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          height: 250,
          width: 250,
          decoration: BoxDecoration(
            color: shimmerPaintColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.image_outlined,
                  size: 48,
                  color: shimmerPaintColor,
                ),
                const SizedBox(height: 12),
                // This Text widget is part of the shimmer effect.
                // It's given a solid background color to create a solid shape for the shader to draw on.
                Container(
                  color: shimmerPaintColor,
                  child: const Text(
                    'Generating image...',
                    style: TextStyle(fontSize: 14, color: shimmerPaintColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shimmer placeholder for presentation generation with label and distinct layout
class PresentationShimmer extends StatelessWidget {
  const PresentationShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    const shimmerPaintColor = Colors.black;

    return Align(
      alignment: Alignment.centerLeft,
      child: CustomShimmer(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor, // This gives the container its shape but is overridden
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: shimmerPaintColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.slideshow_outlined, color: shimmerPaintColor),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(color: shimmerPaintColor, child: const Text('Creating presentation...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: shimmerPaintColor))),
                  const SizedBox(height: 6),
                  Container(color: shimmerPaintColor, child: const Text('Please wait a moment', style: TextStyle(fontSize: 12, color: shimmerPaintColor))),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// Shimmer placeholder for web search with label
class WebSearchShimmer extends StatelessWidget {
  const WebSearchShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    const shimmerPaintColor = Colors.black;

    return Align(
      alignment: Alignment.centerLeft,
      child: CustomShimmer(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public, size: 18, color: shimmerPaintColor),
              const SizedBox(width: 12),
              Container(
                color: shimmerPaintColor,
                child: const Text(
                  'Searching the web...',
                  style: TextStyle(fontSize: 14, color: shimmerPaintColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}