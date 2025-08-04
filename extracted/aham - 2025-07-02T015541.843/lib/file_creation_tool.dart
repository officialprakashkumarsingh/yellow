import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw; // Import PDF package with a prefix
import 'package:share_plus/share_plus.dart';

class FileCreationService {
  
  static Future<File?> createAndSaveSingleFile({
    required String fileName,
    required String content,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsString(content);
      return file;
    } catch (e) {
      print("Error creating single file: $e");
      return null;
    }
  }

  static Future<File?> createAndSaveZipFile({
    required String zipFileName,
    required Map<String, String> filesToInclude,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$zipFileName';
      
      final archive = Archive();
      filesToInclude.forEach((filePath, content) {
        final fileData = Uint8List.fromList(utf8.encode(content));
        final archiveFile = ArchiveFile(filePath, fileData.length, fileData);
        archive.addFile(archiveFile);
      });

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      if (zipData == null) {
        throw Exception("Failed to encode ZIP file.");
      }

      final file = File(path);
      await file.writeAsBytes(zipData);
      return file;
    } catch (e) {
      print("Error creating ZIP file: $e");
      return null;
    }
  }

  // NEW: Method to create multi-page PDFs
  static Future<File?> createAndSavePdfFile({
    required String pdfFileName,
    required List<String> pagesContent,
  }) async {
    try {
      final pdf = pw.Document();
      for (final pageText in pagesContent) {
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Paragraph(text: pageText);
            },
          ),
        );
      }

      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$pdfFileName';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());
      return file;
    } catch (e) {
      print("Error creating PDF file: $e");
      return null;
    }
  }
}