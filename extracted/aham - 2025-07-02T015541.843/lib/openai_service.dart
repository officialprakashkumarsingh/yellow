import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

      debugPrint('OpenAI Request: ${jsonEncode(requestBody)}');
      debugPrint('API URL: ${config.apiBaseUrl}/v1/chat/completions');

      final request = http.Request(
        'POST',
        Uri.parse('${config.apiBaseUrl}/v1/chat/completions'),
      );
      
      request.headers.addAll({
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });
      
      request.body = jsonEncode(requestBody);
      
      final streamedResponse = await http.Client().send(request);
      
      if (streamedResponse.statusCode == 200) {
        // Handle streaming response
        await _handleStreamingResponse(streamedResponse, controller);
      } else {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint('API Error: ${streamedResponse.statusCode} - $errorBody');
        throw Exception('API request failed: ${streamedResponse.statusCode} - $errorBody');
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
    http.StreamedResponse response,
    StreamController<String> controller,
  ) async {
    try {
      String buffer = '';
      
      await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final jsonData = chunk.substring(6).trim();
          
          if (jsonData == '[DONE]') {
            controller.close();
            return;
          }
          
          if (jsonData.isEmpty) continue;
          
          try {
            final data = jsonDecode(jsonData);
            final content = data['choices']?[0]?['delta']?['content'];
            if (content != null && content is String) {
              debugPrint('Streaming chunk: "$content"');
              controller.add(content);
            }
          } catch (e) {
            // Skip invalid JSON lines
            debugPrint('JSON parsing error: $e for data: $jsonData');
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