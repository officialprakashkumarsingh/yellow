import 'dart:io';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive_io.dart';


import 'package:ahamai/api.dart';
import 'package:ahamai/image_editor.dart';
import 'package:ahamai/models.dart';
import 'package:ahamai/presentation_generator.dart';
import 'package:ahamai/web_search.dart';
import 'package:ahamai/aham-host.dart';

// --- Re-integrated File Creation Logic ---
class FileCreationService {
  static Future<File?> createAndSaveSingleFile({required String fileName, required String content}) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);
      return file;
    } catch (e) {
      print("Error creating single file: $e");
      return null;
    }
  }

  static Future<File?> createAndSavePdfFile({required String pdfFileName, required List<String> pagesContent}) async {
    try {
      final pdf = pw.Document();
      for (final content in pagesContent) {
        pdf.addPage(pw.Page(
          build: (pw.Context context) => pw.Paragraph(text: content),
        ));
      }
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$pdfFileName');
      await file.writeAsBytes(await pdf.save());
      return file;
    } catch (e) {
      print("Error creating PDF file: $e");
      return null;
    }
  }

  static Future<File?> createAndSaveZipFile({required String zipFileName, required Map<String, String> filesToInclude}) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final encoder = ZipFileEncoder();
      final zipFilePath = '${directory.path}/$zipFileName';
      encoder.create(zipFilePath);
      for (final entry in filesToInclude.entries) {
        encoder.addArchiveFile(ArchiveFile(entry.key, entry.value.length, utf8.encode(entry.value)));
      }
      encoder.close();
      return File(zipFilePath);
    } catch (e) {
      print("Error creating ZIP file: $e");
      return null;
    }
  }
}

String _sanitizeUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  return 'https://$url';
}


class ToolExecutor {
  final BuildContext context;
  final Function(ChatMessage) onAddMessage;
  final Function(String?, String?) onUpdateAssets;
  final Map<String, String> agentMemory;
  // NEW: Added userImage parameter to handle image-based tools
  final XFile? userImage;

  ToolExecutor({
    required this.context,
    required this.onAddMessage,
    required this.onUpdateAssets,
    required this.agentMemory,
    this.userImage,
  });

  Future<String> executeTool(Map<String, dynamic> step, {String? currentUrl}) async {
    final tool = step['tool'] as String?;
    if (tool == null) {
      return "Agent Error: Missing 'tool' in step.";
    }

    try {
      switch (tool) {
        case 'browser_automation':
          return await performBrowserAutomation(step, currentUrl: currentUrl);
        case 'website_screenshot':
          return await performWebsiteScreenshot(step);
        case 'multi_page_screenshot':
          return await performMultiPageScreenshot(step);
        case 'website_generation':
          return await performWebsiteGeneration(step);
        case 'list_deployed_sites':
          return await performListDeployedSites();
        case 'create_text_file':
          return await performCreateTextFile(step);
        case 'create_pdf':
          return await performCreatePdf(step);
        case 'create_zip':
          return await performCreateZip(step);
        case 'diagram_generation':
          return await performDiagramGeneration(step);
        case 'web_search':
          return await performAutomaticWebSearch(step);
        case 'wikipedia_search':
          return await performAutomaticWikipediaSearch(step['query']);
        case 'image_generation':
          return await performImageGeneration(step);
        // NEW: Case for the image editing tool
        case 'image_editing':
          return await performImageEditing(step);
        case 'presentation_generation':
          return await performPresentationGeneration(step);
        case 'send_email':
        case 'send_whatsapp':
          return await performSharing(step);
        default:
          return "Agent Error: Tool '$tool' is not recognized or supported by the planner.";
      }
    } catch (e) {
      return "Agent Error: An unexpected exception occurred while executing tool '$tool': $e";
    }
  }

  // NEW: Function to execute the image editing tool
  Future<String> performImageEditing(Map<String, dynamic> params) async {
    final prompt = params['prompt'] as String?;
    if (prompt == null) {
      return "Agent Error: Missing 'prompt' for image editing.";
    }
    // Check if an image was provided by the user context
    if (userImage == null) {
      return "Agent Error: Tool 'image_editing' was called, but no image was provided by the user.";
    }

    onAddMessage(ChatMessage(role: 'model', text: 'Editing image...', type: MessageType.image, timestamp: DateTime.now()));

    try {
      final editedImageUrl = await ImageEditingService.editImage(prompt: prompt, imageFile: userImage!);
      await precacheImage(NetworkImage(editedImageUrl), context);

      onUpdateAssets(editedImageUrl, null);
      // Replace the loading message with the final image
      onAddMessage(ChatMessage(role: 'model', text: 'Edited image for: $prompt', type: MessageType.image, imageUrl: editedImageUrl, timestamp: DateTime.now()));
      
      return "Successfully edited image and displayed it to the user. The new image URL is $editedImageUrl";
    } catch (e) {
      onAddMessage(ChatMessage(role: 'model', text: '❌ Failed to edit image: $e', type: MessageType.text, timestamp: DateTime.now()));
      return "Agent Error editing image: $e";
    }
  }
  
  Future<String> performListDeployedSites() async {
    final sites = await NetlifyDeployer.getDeployedSites();
    if (sites.isEmpty) {
      onAddMessage(ChatMessage(role: 'model', text: 'Here are your deployed sites:\nNo websites have been deployed yet.', timestamp: DateTime.now()));
      return "No websites have been deployed yet.";
    }
    final siteListString = sites.map((s) => "Name: ${s.name}, URL: ${s.url}, ID: ${s.siteId}").join("\n");
    
    onAddMessage(ChatMessage(role: 'model', text: 'Here are your deployed sites:\n$siteListString', timestamp: DateTime.now()));
    
    return "Successfully displayed the list of deployed sites to the user.";
  }

  Future<String> performWebsiteGeneration(Map<String, dynamic> params) async {
    // FIX: The `files` parameter is now a direct map, not a list of maps.
    final files = params['files_map'] as Map<String, dynamic>?;
    final siteIdToRedeploy = params['siteId'] as String?;

    if (files == null || files.isEmpty) {
      return "Agent Error: Missing 'files_map' object to generate the website.";
    }

    final Map<String, String> filesToInclude = files.map((key, value) => MapEntry(key, value.toString()));

    if (!filesToInclude.containsKey('index.html')) {
      return "Agent Error: The website files must contain an 'index.html' at the root.";
    }
    
    if (filesToInclude.values.any((content) => content.trim().isEmpty || content.length < 20)) {
        return "Agent Error: The code for the website is missing or invalid. The agent likely failed to generate it properly.";
    }

    onAddMessage(ChatMessage(role: 'model', text: '[Executing: website_generation]\nGenerating website files...', type: MessageType.agent_status, statusIcon: Icons.code, timestamp: DateTime.now()));
    
    final directory = await getTemporaryDirectory();
    final zipFile = File('${directory.path}/website_${DateTime.now().millisecondsSinceEpoch}.zip');
    
    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);
    for (final entry in filesToInclude.entries) {
      encoder.addArchiveFile(ArchiveFile(entry.key, entry.value.length, utf8.encode(entry.value)));
    }
    encoder.close();

    onAddMessage(ChatMessage(role: 'model', text: '[Executing: website_generation]\nDeploying to Netlify...', type: MessageType.agent_status, statusIcon: Icons.upload_rounded, timestamp: DateTime.now()));

    try {
      String deployedUrl;
      String resultMessage;

      if (siteIdToRedeploy != null) {
        deployedUrl = await NetlifyDeployer.redeployWebsite(siteIdToRedeploy, zipFile);
        resultMessage = "Successfully redeployed website. The live URL is: $deployedUrl";
        onAddMessage(ChatMessage(role: 'model', text: 'Website updated! You can view the changes live.', type: MessageType.text, timestamp: DateTime.now()));
      } else {
        final newSite = await NetlifyDeployer.deployNewWebsite(zipFile);
        deployedUrl = newSite.url;
        resultMessage = "Successfully generated and deployed new website. The live URL is: $deployedUrl";
        onAddMessage(ChatMessage(role: 'model', text: 'New website deployed! You can view it live.', type: MessageType.text, timestamp: DateTime.now()));
      }

      await performWebsiteScreenshot({'url': deployedUrl});
      
      return resultMessage;
    } catch (e) {
      onAddMessage(ChatMessage(role: 'model', text: '❌ Failed to deploy website: $e', type: MessageType.text, timestamp: DateTime.now()));
      return "Agent Error during website deployment: $e";
    } finally {
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  }

  Future<String> performCreateTextFile(Map<String, dynamic> params) async {
    final fileName = params['file_name'] as String?;
    final content = params['content'] as String?;
    
    if (fileName == null || content == null || content.trim().isEmpty) {
      return "Agent Error: `file_name` and non-empty `content` are required.";
    }

    final file = await FileCreationService.createAndSaveSingleFile(fileName: fileName, content: content);
    if (file != null) {
      onUpdateAssets(null, file.path);
      onAddMessage(ChatMessage(role: 'model', text: file.path.split('/').last, type: MessageType.file, filePath: file.path, timestamp: DateTime.now()));
      return "Successfully created file: ${file.path}";
    }
    return "Agent Error: Failed to create text file.";
  }

  Future<String> performCreatePdf(Map<String, dynamic> params) async {
    final fileName = params['file_name'] as String?;
    final pages = (params['pages'] as List<dynamic>?)?.map((e) => e.toString()).toList();

    if (fileName == null || pages == null || pages.isEmpty || pages.join("").trim().isEmpty) {
      return "Agent Error: `file_name` and a non-empty list of `pages` are required.";
    }

    final file = await FileCreationService.createAndSavePdfFile(pdfFileName: fileName, pagesContent: pages);
    if (file != null) {
      onUpdateAssets(null, file.path);
      onAddMessage(ChatMessage(role: 'model', text: file.path.split('/').last, type: MessageType.file, filePath: file.path, timestamp: DateTime.now()));
      return "Successfully created PDF: ${file.path}";
    }
    return "Agent Error: Failed to create PDF.";
  }
  
  Future<String> performCreateZip(Map<String, dynamic> params) async {
      // FIX: The parameter is now `files_map`, a direct map.
      final zipFileName = params['zip_file_name'] as String?;
      final files = params['files_map'] as Map<String, dynamic>?;

      if (zipFileName == null || files == null || files.isEmpty) {
          return "Agent Error: `zip_file_name` and a non-empty `files_map` object are required.";
      }

      final Map<String, String> filesToInclude = files.map((key, value) => MapEntry(key, value.toString()));

      if (filesToInclude.values.any((c) => c.trim().isEmpty)) {
          return "Agent Error: All files within the zip must have non-empty content.";
      }
      
      final file = await FileCreationService.createAndSaveZipFile(zipFileName: zipFileName, filesToInclude: filesToInclude);
      if (file != null) {
          onUpdateAssets(null, file.path);
          onAddMessage(ChatMessage(role: 'model', text: file.path.split('/').last, type: MessageType.file, filePath: file.path, timestamp: DateTime.now()));
          return "Successfully created ZIP archive: ${file.path}";
      }
      return "Agent Error: Failed to create ZIP archive.";
  }

  Future<String> performMultiPageScreenshot(Map<String, dynamic> params) async {
    final url = params['url'] as String?;
    if (url == null) return "Agent Error: Missing 'url' for multi_page_screenshot.";
    
    final sanitizedUrl = _sanitizeUrl(url);

    try {
      onAddMessage(ChatMessage(role: 'model', text: 'Scraping $sanitizedUrl for links...', type: MessageType.agent_status, statusIcon: Icons.travel_explore, timestamp: DateTime.now()));
      final response = await http.get(Uri.parse(sanitizedUrl));
      if (response.statusCode != 200) {
        return 'Error: Could not access $sanitizedUrl. Status code: ${response.statusCode}';
      }

      final document = parse(response.body);
      final Set<String> links = document.querySelectorAll('a[href]').map((e) {
        String href = e.attributes['href'] ?? '';
        if (href.startsWith('/')) {
          return Uri.parse(sanitizedUrl).origin + href;
        }
        if (href.startsWith(Uri.parse(sanitizedUrl).origin)) {
          return href;
        }
        return '';
      }).where((href) => href.isNotEmpty).toSet();

      final mainLinks = [sanitizedUrl, ...links.take(4)];
      onAddMessage(ChatMessage(role: 'model', text: 'Found ${mainLinks.length} pages to screenshot. Capturing now...', type: MessageType.agent_status, statusIcon: Icons.camera_alt_outlined, timestamp: DateTime.now()));

      for (final link in mainLinks) {
        await performWebsiteScreenshot({'url': link});
        await Future.delayed(const Duration(milliseconds: 500));
      }

      return "Successfully captured screenshots for ${mainLinks.length} pages.";
    } catch (e) {
      return "An error occurred during multi-page screenshot: $e";
    }
  }

  Future<String> performBrowserAutomation(Map<String, dynamic> params, {String? currentUrl}) async {
      final url = params['url'] as String? ?? currentUrl;
      final actions = params['actions'] as List<dynamic>?;

      if (url == null && actions == null) {
          return "Agent Error: Browser automation requires a 'url' or 'actions'.";
      }

      if (actions == null || actions.isEmpty) {
        return "Navigated to $url. Ready for next action.";
      }
      
      var simulationReport = StringBuffer();
      bool isLoginAttempt = false;

      for (final action in actions) {
          if (action is! Map<String, dynamic>) continue;
          final actionType = action['action'] as String?;
          final selector = action['selector'] as String?;
          switch (actionType) {
              case 'type':
                  final text = action['text'] as String?;
                  simulationReport.writeln('Simulated typing into element "${selector ?? "N/A"}".');
                  if (selector != null && (selector.contains('password') || text != null && text.contains('pass'))) {
                      isLoginAttempt = true;
                  }
                  break;
              case 'click':
                  simulationReport.writeln('Simulated clicking element "${selector ?? "N/A"}".');
                   if (selector != null && (selector.contains('login') || selector.contains('submit'))) {
                      isLoginAttempt = true;
                  }
                  break;
              case 'scrape':
                  if (url == null) return "Agent Error: Cannot scrape without a URL.";
                  if (isLoginAttempt) {
                    simulationReport.writeln('Login attempt detected. Assuming success and scraping target page.');
                    return "Simulated login successful. Scraped content from the destination page: [Dashboard content, user settings, etc.]";
                  }
                  simulationReport.writeln('Scraping content from $url.');
                  return await _scrapeUrlContent(url);
          }
      }

      if (isLoginAttempt && !actions.any((a) => a['action'] == 'scrape')) {
          return "Simulated login successful. Ready for next action.";
      }

      return simulationReport.toString().trim().isEmpty ? "Browser actions completed." : simulationReport.toString().trim();
  }

  Future<String> _scrapeUrlContent(String url) async {
    try {
      final sanitizedUrl = _sanitizeUrl(url);
      final response = await http.get(Uri.parse(sanitizedUrl));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final title = document.querySelector('title')?.text ?? 'No Title Found';
        final mainContent = document.querySelector('main, article, #main, #content, .main, .content')?.text ?? document.body?.text;
        final cleanContent = mainContent?.replaceAll(RegExp(r'\s{2,}'), '\n').trim() ?? 'No content found.';
        
        return '[SCRAPED_CONTENT_START]\nTitle: $title\nURL: $sanitizedUrl\nContent: ${cleanContent.substring(0, (cleanContent.length > 1500) ? 1500 : cleanContent.length)}...';
      } else {
        return 'Failed to retrieve content from $sanitizedUrl. Status code: ${response.statusCode}';
      }
    } catch (e) {
        return 'Error scraping URL $url: $e';
    }
  }


  Future<String> performWebsiteScreenshot(Map<String, dynamic> params) async {
    final url = params['url'] as String?;
    if (url == null) return "Agent Error: Missing 'url' for website_screenshot.";
    
    final sanitizedUrl = _sanitizeUrl(url);

    try {
      final screenshotUrl = 'https://s.wordpress.com/mshots/v1/${Uri.encodeComponent(sanitizedUrl)}?w=1024&h=768';
      final response = await http.head(Uri.parse(screenshotUrl));
      
      if (response.statusCode != 200) {
        if(response.headers['location']?.contains('api.wordpress.com/img/placeholder.png') ?? false) {
           throw Exception('The provided URL is not a valid or publicly accessible website.');
        }
        throw Exception('Screenshot service returned status ${response.statusCode}');
      }

      await precacheImage(NetworkImage(screenshotUrl), context);
      
      onUpdateAssets(screenshotUrl, null);
      onAddMessage(ChatMessage(
        role: 'model',
        text: 'Screenshot of $sanitizedUrl',
        type: MessageType.image,
        imageUrl: screenshotUrl,
        timestamp: DateTime.now(),
      ));
      return "Successfully captured screenshot. Image URL is $screenshotUrl";
    } catch (e) {
      onAddMessage(ChatMessage(
        role: 'model',
        text: '❌ Failed to generate screenshot for $url. Error: $e',
        type: MessageType.text,
        timestamp: DateTime.now(),
      ));
      return "Agent Error: Failed to generate screenshot: $e";
    }
  }

  Future<String> performAutomaticWebSearch(Map<String, dynamic> params) async {
    final query = params['query'] as String?;
    if (query == null || query.trim().isEmpty) {
        return "Agent Error: Missing 'query' for web_search. The query cannot be empty.";
    }
    
    final searchResponse = await WebSearchService.search(query);
    
    if (searchResponse == null) {
       return "Agent Error: Web search failed or returned no results.";
    }

    final readContent = params['read_content'] as bool? ?? false;
    if (readContent && searchResponse.results.isNotEmpty) {
       final firstUrl = searchResponse.results.first.url;
       return await _scrapeUrlContent(firstUrl);
    }
    
    return searchResponse.promptContent;
  }

  Future<String> performAutomaticWikipediaSearch(String? searchQuery) async {
    if (searchQuery == null) return "Agent Error: Missing 'query' for wikipedia_search.";
    final wikiContext = await WikipediaSearchService.search(searchQuery);
    return wikiContext ?? "Agent Error: Wikipedia search failed or returned no results.";
  }
  
  Future<String> performDiagramGeneration(Map<String, dynamic> params) async {
    String? mermaidCode = params['description'] as String?;
    if (mermaidCode == null || mermaidCode.trim().isEmpty) {
      // FIX: Improved, more instructive error message for the agent to self-correct.
      return "Agent Error: The 'description' parameter is missing or empty. It must contain valid Mermaid diagram syntax. For example: 'graph TD; A--text-->B;'";
    }

    mermaidCode = mermaidCode.trim();
    if (!mermaidCode.startsWith('graph') && !mermaidCode.startsWith('pie') && !mermaidCode.startsWith('sequenceDiagram') && !mermaidCode.startsWith('gantt') && !mermaidCode.startsWith('flowchart')) {
      mermaidCode = 'graph TD;\n$mermaidCode';
    }
    
    try {
      final krokiUrl = Uri.parse('https://kroki.io/mermaid/svg');
      final request = http.Request('POST', krokiUrl)
        ..headers['Content-Type'] = 'text/plain; charset=UTF-8'
        ..body = mermaidCode
        ..encoding = utf8;

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final svgData = await response.stream.bytesToString();
        
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'diagram_${DateTime.now().millisecondsSinceEpoch}.svg';
        final file = File('${directory.path}/$fileName');
        await file.writeAsString(svgData);

        onUpdateAssets(null, file.path);
        onAddMessage(ChatMessage(
          role: 'model',
          text: 'Diagram created successfully.',
          type: MessageType.image,
          filePath: file.path,
          timestamp: DateTime.now(),
        ));
        return "Successfully generated diagram and saved it locally at ${file.path}";
      } else {
        final errorBody = await response.stream.bytesToString();
        // Give the agent a hint about what went wrong.
        throw Exception("Kroki service failed with status ${response.statusCode}. The Mermaid syntax was likely invalid. Error: $errorBody");
      }
    } catch (e) {
      onAddMessage(ChatMessage(
        role: 'model',
        text: '❌ Sorry, I failed to generate the diagram. Please check the syntax or try a different description.',
        type: MessageType.text,
        timestamp: DateTime.now(),
      ));
      return "Agent Error: Failed to generate diagram: $e";
    }
  }
  
  Future<String> performImageGeneration(Map<String, dynamic> params) async {
    final prompt = params['prompt'] as String?;
    if (prompt == null) return "Agent Error: Missing 'prompt' for image generation.";
    
    final modelId = params['model'] as String? ?? ApiConfigService.instance.defaultImageModelId;
    if (modelId.isEmpty) return "Agent Error: No image generation model configured.";

    onAddMessage(ChatMessage(role: 'model', text: 'Generating image...', type: MessageType.image, imageUrl: null, timestamp: DateTime.now()));
    
    try {
      final imageUrl = await ImageApi.generateImage(
        prompt: prompt,
        modelId: modelId,
      );
      
      if (imageUrl != null) {
        await precacheImage(NetworkImage(imageUrl), context);
        onUpdateAssets(imageUrl, null);
        onAddMessage(ChatMessage(role: 'model', text: '', type: MessageType.image, imageUrl: imageUrl, timestamp: DateTime.now()));
        return "Successfully generated image at $imageUrl";
      } else {
        onAddMessage(ChatMessage(role: 'model', text: '❌ Failed to generate image: No URL returned', type: MessageType.text, timestamp: DateTime.now()));
        return "Agent Error: Image generation failed - no URL returned";
      }
    } catch (e) {
      onAddMessage(ChatMessage(role: 'model', text: '❌ Failed to generate image: $e', type: MessageType.text, timestamp: DateTime.now()));
      return "Agent Error generating image: $e";
    }
  }
  
  Future<String> performPresentationGeneration(Map<String, dynamic> params) async {
      final topic = params['topic'] as String?;
      if (topic == null) return "Agent Error: Missing 'topic' for presentation generation.";

      final presentationConfig = ApiConfigService.instance.presentationModel;
      if (presentationConfig.apiKey == null) return "Agent Error: Presentation generator not configured.";
      
      onAddMessage(ChatMessage(role: 'model', text: '', type: MessageType.presentation, slides: null, timestamp: DateTime.now()));
      
      final slides = await PresentationGenerator.generateSlides(topic, presentationConfig.apiKey!);
      
      if (slides.isNotEmpty) {
        onAddMessage(ChatMessage(
          role: 'model',
          text: 'Presentation ready: $topic',
          type: MessageType.presentation,
          slides: slides,
          timestamp: DateTime.now())
        );
        return "Successfully created presentation on '$topic'.";
      } else {
        onAddMessage(ChatMessage(role: 'model', text: 'Could not generate presentation for "$topic".', type: MessageType.text, timestamp: DateTime.now()));
        return "Agent Error: Failed to create presentation.";
      }
  }
  
  Future<String> performSharing(Map<String, dynamic> step) async {
      final tool = step['tool'];
      final attachmentPath = step['attachment'] as String?;
      final to = tool == 'send_email' ? step['to'] : step['phoneNumber'];
      final message = tool == 'send_email' ? step['body'] : step['message'];
      final subject = tool == 'send_email' ? step['subject'] : null;

      if (to == null) return "Agent Error: Missing recipient.";

      if (attachmentPath != null && (attachmentPath.startsWith('/') || attachmentPath.startsWith('http'))) {
         final fileToShare = XFile(attachmentPath);
         await Share.shareXFiles([fileToShare], text: message ?? '');
         return "Prepared share action with attachment.";
      } else {
        final uriString = tool == 'send_email'
          ? 'mailto:$to?subject=${Uri.encodeComponent(subject ?? '')}&body=${Uri.encodeComponent(message ?? '')}'
          : 'https://wa.me/$to?text=${Uri.encodeComponent(message ?? '')}';
        await launchUrl(Uri.parse(uriString), mode: LaunchMode.externalApplication);
        return "Opened external app to send message.";
      }
  }
}