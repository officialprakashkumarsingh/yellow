import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'theme.dart';

/// A data class to hold information about a processed file attachment.
class ChatAttachment {
  final String fileName;
  final String content;
  final List<String> containedFileNames; // Specifically for zip files

  ChatAttachment({
    required this.fileName,
    required this.content,
    this.containedFileNames = const [],
  });
}

/// A service class to handle file picking and processing logic.
class FileProcessingService {
  // Extracts text from PDF bytes. Moved from chat_screen.dart.
  static Future<String> _extractTextFromPdfBytes(List<int> bytes) async {
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final String text = PdfTextExtractor(document).extractText();
    document.dispose();
    return text;
  }

  // Processes a ZIP archive.
  static Future<ChatAttachment> _processZip(String fileName, Uint8List fileBytes) async {
    final archive = ZipDecoder().decodeBytes(fileBytes);
    final buffer = StringBuffer();
    final List<String> containedFileNames = [];

    buffer.writeln("Here is the content of the ZIP file '$fileName':");

    for (final file in archive) {
      if (file.isFile) {
        final fName = file.name;
        containedFileNames.add(fName);
        buffer.writeln('\n--- FILE: $fName ---');
        // Attempt to decode as UTF-8, fall back if it fails.
        try {
          final fileContent = utf8.decode(file.content as List<int>);
          buffer.writeln(fileContent);
        } catch (e) {
          buffer.writeln('[Could not decode content for this file]');
        }
      }
    }
    return ChatAttachment(
      fileName: fileName,
      content: buffer.toString(),
      containedFileNames: containedFileNames,
    );
  }

  // Picks a file using the file picker and processes its content.
  static Future<ChatAttachment?> pickAndProcessFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'zip', 'txt', 'md', 'py', 'java', 'js', 'ts', 'dart',
        'html', 'css', 'json', 'c', 'cpp', 'cs', 'go', 'kt', 'php', 'rb', 'rs', 'swift'
      ],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      return null;
    }

    final file = result.files.single;
    final fileName = file.name;
    final fileBytes = file.bytes!;
    final extension = p.extension(fileName).toLowerCase();

    if (extension == '.zip') {
      return await compute((Map<String, dynamic> params) => _processZip(params['name'], params['bytes']), {'name': fileName, 'bytes': fileBytes});
    } else if (extension == '.pdf') {
      final text = await compute(_extractTextFromPdfBytes, fileBytes.toList());
      return ChatAttachment(fileName: fileName, content: text);
    } else {
      // Handle as a generic text file
      try {
        final text = utf8.decode(fileBytes);
        return ChatAttachment(fileName: fileName, content: text);
      } catch (e) {
        // If it's not valid UTF-8, we can't process it as text.
        print("Error decoding text file: $e");
        return null;
      }
    }
  }
}

/// A widget to display a preview of the attached file in the chat input area.
class AttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  final VoidCallback onClear;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = !isLightTheme(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
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
              Icon(
                attachment.containedFileNames.isNotEmpty ? Icons.folder_zip_outlined : Icons.description_outlined,
                size: 24,
                color: Theme.of(context).iconTheme.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  attachment.fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close, size: 20),
                  ),
                ),
              ),
            ],
          ),
          if (attachment.containedFileNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                iconColor: Theme.of(context).iconTheme.color,
                collapsedIconColor: Theme.of(context).iconTheme.color,
                title: Text(
                  '${attachment.containedFileNames.length} files in ZIP',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: attachment.containedFileNames.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                          child: Text(
                            attachment.containedFileNames[index],
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? draculaComment : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}