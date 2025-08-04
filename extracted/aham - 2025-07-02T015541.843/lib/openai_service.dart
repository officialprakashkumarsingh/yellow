import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ahamai/api.dart';
import 'package:ahamai/models.dart';

class OpenAIService {
  static final OpenAIService instance = OpenAIService._internal();
  OpenAIService._internal();

  Future<Stream<String>> streamChatCompletion({
    required String prompt,
    List<ChatMessage>? messages,
    String? systemPrompt,
    Uint8List? imageBytes,
    String? modelId,
  }) async {
    final config = ApiConfigService.instance;
    final selectedModel = modelId != null 
        ? config.getModelConfigById(modelId) ?? config.selectedModel
        : config.selectedModel;

    final controller = StreamController<String>();
    
    try {
      final requestMessages = _buildMessages(
        prompt: prompt,
        messages: messages,
        systemPrompt: systemPrompt,
        imageBytes: imageBytes,
      );

      final requestBody = {
        'model': selectedModel.modelId,
        'messages': requestMessages,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 4000,
      };

      final response = await http.post(
        Uri.parse('${config.apiBaseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // Handle streaming response
        await _handleStreamingResponse(response, controller);
      } else {
        throw Exception('API request failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      controller.addError('Error: $e');
      debugPrint('OpenAI Service Error: $e');
    }

    return controller.stream;
  }

  Future<String> generateCompletion({
    required String prompt,
    List<ChatMessage>? messages,
    String? systemPrompt,
    Uint8List? imageBytes,
    String? modelId,
  }) async {
    final config = ApiConfigService.instance;
    final selectedModel = modelId != null 
        ? config.getModelConfigById(modelId) ?? config.selectedModel
        : config.selectedModel;

    try {
      final requestMessages = _buildMessages(
        prompt: prompt,
        messages: messages,
        systemPrompt: systemPrompt,
        imageBytes: imageBytes,
      );

      final requestBody = {
        'model': selectedModel.modelId,
        'messages': requestMessages,
        'temperature': 0.7,
        'max_tokens': 4000,
      };

      final response = await http.post(
        Uri.parse('${config.apiBaseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] ?? 'No response';
      } else {
        throw Exception('API request failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('OpenAI Service Error: $e');
      return 'Error: Failed to generate response. Please try again.';
    }
  }

  List<Map<String, dynamic>> _buildMessages({
    required String prompt,
    List<ChatMessage>? messages,
    String? systemPrompt,
    Uint8List? imageBytes,
  }) {
    final requestMessages = <Map<String, dynamic>>[];

    // Add system prompt if provided
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      requestMessages.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }

    // Add conversation history
    if (messages != null) {
      for (final message in messages.take(20)) { // Limit history to prevent token overflow
        final content = <Map<String, dynamic>>[];
        
        // Add text content
        if (message.text.isNotEmpty) {
          content.add({
            'type': 'text',
            'text': message.text,
          });
        }

        // Add image if present (for vision models)
        if (message.imageBytes != null) {
          final base64Image = base64Encode(message.imageBytes!);
          content.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            },
          });
        }

        if (content.isNotEmpty) {
          requestMessages.add({
            'role': message.role == 'user' ? 'user' : 'assistant',
            'content': content.length == 1 && content[0]['type'] == 'text' 
                ? content[0]['text'] 
                : content,
          });
        }
      }
    }

    // Add current user message
    final currentContent = <Map<String, dynamic>>[];
    
    if (prompt.isNotEmpty) {
      currentContent.add({
        'type': 'text',
        'text': prompt,
      });
    }

    if (imageBytes != null) {
      final base64Image = base64Encode(imageBytes);
      currentContent.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,$base64Image',
        },
      });
    }

    if (currentContent.isNotEmpty) {
      requestMessages.add({
        'role': 'user',
        'content': currentContent.length == 1 && currentContent[0]['type'] == 'text' 
            ? currentContent[0]['text'] 
            : currentContent,
      });
    }

    return requestMessages;
  }

  Future<void> _handleStreamingResponse(
    http.Response response, 
    StreamController<String> controller,
  ) async {
    try {
      final responseBody = response.body;
      final lines = responseBody.split('\n');
      
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final jsonData = line.substring(6);
          if (jsonData.trim() == '[DONE]') {
            controller.close();
            return;
          }
          
          try {
            final data = jsonDecode(jsonData);
            final content = data['choices']?[0]?['delta']?['content'];
            if (content != null) {
              controller.add(content);
            }
          } catch (e) {
            // Skip invalid JSON lines
            continue;
          }
        }
      }
      controller.close();
    } catch (e) {
      controller.addError('Streaming error: $e');
      controller.close();
    }
  }
}

// Legacy compatibility class for presentations
class GenerativeModel {
  final String model;
  final String apiKey;

  GenerativeModel({required this.model, required this.apiKey});

  Future<GenerateContentResponse> generateContent(List<Content> contents) async {
    final prompt = contents.map((c) => c.parts.map((p) => p.text).join(' ')).join(' ');
    
    final result = await OpenAIService.instance.generateCompletion(
      prompt: prompt,
      modelId: model,
    );
    
    return GenerateContentResponse(result);
  }
}

class Content {
  final List<TextPart> parts;
  Content.text(String text) : parts = [TextPart(text)];
}

class TextPart {
  final String text;
  TextPart(this.text);
}

class GenerateContentResponse {
  final String? text;
  GenerateContentResponse(this.text);
}