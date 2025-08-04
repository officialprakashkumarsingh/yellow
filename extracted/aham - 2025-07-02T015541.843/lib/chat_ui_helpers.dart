import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'theme.dart';
import 'ui_widgets.dart';
import 'web_search.dart';
import 'package:ahamai/models.dart';

class DeployedSitesListMessage extends StatelessWidget {
  final ChatMessage message;
  final Function(String name, String siteId) onEdit;

  const DeployedSitesListMessage({
    super.key,
    required this.message,
    required this.onEdit,
  });

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
       print('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = message.text.replaceFirst('Here are your deployed sites:\n', '');
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty && l.contains('Name:')).toList();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Your Deployed Sites",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (content == "No websites have been deployed yet.")
              Text(content, style: theme.textTheme.bodyMedium)
            else
              ...lines.map((line) {
                final parts = line.split(', ');
                final name = parts.firstWhere((p) => p.startsWith('Name:'), orElse: () => '').substring(6);
                final url = parts.firstWhere((p) => p.startsWith('URL:'), orElse: () => '').substring(5);
                final siteId = parts.firstWhere((p) => p.startsWith('ID:'), orElse: () => '').substring(4);
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _launchUrl(url),
                              child: Text(
                                url,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                        onPressed: () => onEdit(name, siteId),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      )
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}


class ScrapedContentMessage extends StatelessWidget {
  final ChatMessage message;

  const ScrapedContentMessage({super.key, required this.message});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
       print('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message.text.replaceFirst('[SCRAPED_CONTENT_START]\n', '');
    
    String title = 'Scraped Content';
    String url = '';
    String content = text;

    final lines = text.split('\n');
    if (lines.length >= 3) {
      title = lines.firstWhere((l) => l.startsWith('Title: '), orElse: () => 'Title: Scraped Content').substring(7);
      url = lines.firstWhere((l) => l.startsWith('URL: '), orElse: () => '').substring(5);
      content = lines.skip(2).join('\n').replaceFirst('Content: ', '');
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (url.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                child: InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    url,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              maxLines: 15,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}


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
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({super.key, required this.result});

  final SearchResult result;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
       print('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _launchUrl(result.url),
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
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
                    errorBuilder: (_, __, ___) => Icon(Icons.public, size: 16, color: theme.hintColor),
                  )
                else
                  Icon(Icons.public, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    Uri.parse(result.url).host,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                result.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.9)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImageMessage extends StatefulWidget {
  final ChatMessage message;
  final void Function(String message, {bool isError}) onShowSnackbar;

  const ImageMessage({
    super.key, 
    required this.message, 
    required this.onShowSnackbar,
  });

  @override
  State<ImageMessage> createState() => _ImageMessageState();
}

class _ImageMessageState extends State<ImageMessage> {
  bool _isSharing = false;

  Future<void> _shareImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    widget.onShowSnackbar('Preparing image...', isError: false);

    try {
      final imageUrl = widget.message.imageUrl!;
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final imageBytes = response.bodyBytes;
        final imageName = imageUrl.split('/').last.split('?').first;
        final xFile = XFile.fromData(
          imageBytes,
          mimeType: 'image/png',
          name: imageName.contains('.') ? imageName : '$imageName.png',
        );
        await Share.shareXFiles([xFile], text: 'Image generated by AhamAI');
      } else {
        throw Exception('Failed to download image: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        widget.onShowSnackbar('Error sharing image: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor),
                child: Image.network(
                  widget.message.imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator()));
                  },
                  errorBuilder: (context, error, stackTrace) => const AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: Icon(Icons.broken_image, size: 40)),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: GlassmorphismPanel(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _isSharing
                        ? const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.save_alt_rounded),
                            iconSize: 22,
                            tooltip: 'Save or Share Image',
                            onPressed: _shareImage,
                          ),
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

class PresentationMessage extends StatelessWidget {
  final ChatMessage message;
  const PresentationMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(isDark ? 0.4 : 1.0),
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.7)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const FileMessageWidget({super.key, required this.message});

  Future<String> _getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      int bytes = await file.length();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '0 B';
  }

  Widget _getIconForFile(BuildContext context, String fileName) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withOpacity(0.8);
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'zip':
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.folder_zip_outlined, color: iconColor, size: 28),
            Text('zip', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: iconColor)),
          ],
        );
      case 'pdf':
        return Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade700, size: 28);
      case 'html':
      case 'css':
      case 'js':
      case 'dart':
      case 'py':
      case 'c':
      case 'cpp':
        return Icon(Icons.code_rounded, color: iconColor, size: 28);
      case 'json':
        return Icon(Icons.data_object_rounded, color: iconColor, size: 28);
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icon(Icons.image_outlined, color: iconColor, size: 28);
      default:
        return Icon(Icons.description_outlined, color: iconColor, size: 28);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: GlassmorphismPanel(
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              if (message.filePath != null) {
                Share.shareXFiles([XFile(message.filePath!)], text: 'Here is your file: ${message.text}');
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Row(
                children: [
                  _getIconForFile(context, message.text),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.text,
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<String>(
                          future: _getFileSize(message.filePath ?? ''),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.data ?? 'Calculating...',
                              style: theme.textTheme.bodySmall,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(opacity: _animation.value, child: Icon(Icons.circle, size: widget.size, color: Theme.of(context).elevatedButtonTheme.style?.backgroundColor?.resolve({}))),
    );
  }
}

class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  final List<Animation<double>> _animations = [];
  final int dotCount = 3;
  final double dotSize = 8.0;
  final double spacing = 2.0;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(dotCount, (index) => AnimationController(vsync: this, duration: const Duration(milliseconds: 300)));

    for (int i = 0; i < dotCount; i++) {
      _animations.add(Tween<double>(begin: 0, end: -dotSize).animate(CurvedAnimation(parent: _controllers[i], curve: Curves.easeInOut)));
      _controllers[i].addStatusListener((status) {
        if (status == AnimationStatus.completed) _controllers[i].reverse();
      });
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].forward();
      });
    }

    _controllers.first.addStatusListener((status) {
       if (status == AnimationStatus.dismissed) {
         for (int i = 0; i < dotCount; i++) {
            Future.delayed(Duration(milliseconds: i * 150), () {
              if (mounted) _controllers[i].forward();
            });
         }
       }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.grey[400] : Colors.grey[600];
    
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: GlassmorphismPanel(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(dotCount, (index) {
                return AnimatedBuilder(
                  animation: _animations[index],
                  builder: (context, child) => Transform.translate(offset: Offset(0, _animations[index].value), child: child),
                  child: Container(
                    width: dotSize, height: dotSize,
                    margin: EdgeInsets.only(left: index == 0 ? 0 : spacing, right: index == dotCount - 1 ? 0 : spacing),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class MultiStepIndicator extends StatefulWidget {
  final IconData icon;
  final List<String> activities;
  const MultiStepIndicator({super.key, required this.icon, required this.activities});

  @override
  State<MultiStepIndicator> createState() => _MultiStepIndicatorState();
}

class _MultiStepIndicatorState extends State<MultiStepIndicator> {
  int _currentActivityIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.activities.isNotEmpty) {
      _timer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
        if (mounted) setState(() => _currentActivityIndex = (_currentActivityIndex + 1) % widget.activities.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 18, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7)),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.0, 0.3), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                widget.activities.isEmpty ? 'Processing...' : widget.activities[_currentActivityIndex],
                key: ValueKey<int>(_currentActivityIndex),
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileUploadIndicator extends StatelessWidget {
  const FileUploadIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const MultiStepIndicator(icon: Icons.attach_file_rounded, activities: ["Processing file...", "Analyzing content...", "Getting it ready..."]);
  }
}

class ImageShimmer extends StatefulWidget {
  const ImageShimmer({super.key});
  @override
  State<ImageShimmer> createState() => _ImageShimmerState();
}

class _ImageShimmerState extends State<ImageShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade50;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 16.0),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) {
                return LinearGradient(
                  colors: [baseColor, highlightColor, baseColor],
                  stops: const [0.4, 0.5, 0.6],
                  begin: const Alignment(-1.5, -0.3),
                  end: const Alignment(1.5, 0.3),
                  transform: _SlidingGradientTransform(percent: _controller.value),
                ).createShader(bounds);
              },
              child: child,
            );
          },
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.percent});
  final double percent;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent * 2.5 - (bounds.width * 1.5), 0.0, 0.0);
  }
}

class PresentationShimmer extends StatelessWidget {
  const PresentationShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const MultiStepIndicator(
      icon: Icons.slideshow_outlined,
      activities: ['Structuring the content...', 'Designing the slides...', 'Adding the visuals...', 'Finalizing presentation...'],
    );
  }
}

class WikipediaSearchShimmer extends StatelessWidget {
  const WikipediaSearchShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 18, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7)),
            const SizedBox(width: 12),
            Text('Searching Wikipedia...', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

class WebSearchShimmer extends StatelessWidget {
  const WebSearchShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 18, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7)),
            const SizedBox(width: 12),
            Text('Searching the web...', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

class FileCreationShimmer extends StatelessWidget {
  const FileCreationShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 18, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7)),
            const SizedBox(width: 12),
            Text('Creating your file...', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

class EmailShimmer extends StatelessWidget {
  const EmailShimmer({super.key});
  @override
  Widget build(BuildContext context) => const MultiStepIndicator(icon: Icons.mail_outline_rounded, activities: ['Preparing email...']);
}

class WhatsAppShimmer extends StatelessWidget {
  const WhatsAppShimmer({super.key});
  @override
  Widget build(BuildContext context) => const MultiStepIndicator(icon: CupertinoIcons.chat_bubble_2, activities: ['Opening WhatsApp...']);
}

class AutonomousAgentShimmer extends StatelessWidget {
  const AutonomousAgentShimmer({super.key});
  @override
  Widget build(BuildContext context) => const MultiStepIndicator(
    icon: CupertinoIcons.sparkles,
    activities: [
      'Deconstructing complex goal...',
      'Formulating multi-tool plan...',
      'Executing browser automation...',
      'Generating charts and diagrams...',
      'Synthesizing assets into files...',
      'Compiling final AGI report...'
      ]
  );
}

class DiagramShimmer extends StatelessWidget {
  const DiagramShimmer({super.key});
  @override
  Widget build(BuildContext context) => const MultiStepIndicator(
    icon: Icons.insights_rounded,
    activities: [
      'Parsing diagram structure...',
      'Rendering chart data...',
      'Generating visualization...',
      'Finalizing diagram...'
      ]
  );
}