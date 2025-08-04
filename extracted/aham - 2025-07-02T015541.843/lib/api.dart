import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiConfigService {
  ApiConfigService._privateConstructor();
  static final ApiConfigService instance = ApiConfigService._privateConstructor();

  List<ChatModelConfig> _availableModels = [];
  bool _isInitialized = false;
  String _selectedModelId = 'gpt-4o-mini'; // Default model

  // API Configuration
  static const String _apiBaseUrl = 'https://ahamai-api.officialprakashkrsingh.workers.dev';
  static const String _apiKey = 'ahamaibyprakash25';

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      // Fetch available models from v1/models endpoint
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/v1/models'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> models = data['data'] ?? [];
        
        _availableModels = models.map((model) => ChatModelConfig(
          displayName: _formatModelName(model['id'] ?? 'Unknown Model'),
          modelId: model['id'] ?? 'gpt-4o-mini',
          provider: 'ahamai',
          type: 'chat',
          status: 'active',
          description: model['description'] ?? 'AI Model',
          apiKey: _apiKey,
          apiUrl: _apiBaseUrl,
        )).toList();
        
        _isInitialized = true;
        debugPrint("API configuration loaded successfully. Found ${_availableModels.length} models.");
      } else {
        throw Exception('Failed to load models: Status code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Warning: Could not load models from API. Using fallback. Error: $e");
      // Fallback to default models if API fails
      _availableModels = [
        ChatModelConfig(
          displayName: 'GPT-4o Mini',
          modelId: 'gpt-4o-mini',
          provider: 'ahamai',
          type: 'chat',
          status: 'active',
          description: 'Fast and efficient model',
          apiKey: _apiKey,
          apiUrl: _apiBaseUrl,
        ),
        ChatModelConfig(
          displayName: 'GPT-4o',
          modelId: 'gpt-4o',
          provider: 'ahamai',
          type: 'chat',
          status: 'active',
          description: 'Advanced reasoning model',
          apiKey: _apiKey,
          apiUrl: _apiBaseUrl,
        ),
      ];
      _isInitialized = true;
    }
  }

  String _formatModelName(String modelId) {
    // Convert model IDs to user-friendly names
    switch (modelId.toLowerCase()) {
      case 'gpt-4o-mini':
        return 'GPT-4o Mini';
      case 'gpt-4o':
        return 'GPT-4o';
      case 'gpt-4-turbo':
        return 'GPT-4 Turbo';
      case 'gpt-3.5-turbo':
        return 'GPT-3.5 Turbo';
      case 'claude-3-5-sonnet-20241022':
        return 'Claude 3.5 Sonnet';
      case 'claude-3-haiku-20240307':
        return 'Claude 3 Haiku';
      case 'gemini-2.0-flash-exp':
        return 'Gemini 2.0 Flash';
      case 'gemini-1.5-pro':
        return 'Gemini 1.5 Pro';
      default:
        return modelId.replaceAll('-', ' ').split(' ')
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join(' ');
    }
  }

  String get defaultModelId {
    if (!_isInitialized || _availableModels.isEmpty) return 'gpt-4o-mini';
    return _selectedModelId;
  }

  List<ChatModelConfig> get chatModels {
    return _availableModels;
  }

  ChatModelConfig? getModelConfigById(String modelId) {
    if (_availableModels.isEmpty) return null;
    try {
      return _availableModels.firstWhere((m) => m.modelId == modelId);
    } catch (e) {
      return _availableModels.first;
    }
  }

  // Unified model usage - use the same selected model for all tasks
  ChatModelConfig get selectedModel {
    return getModelConfigById(_selectedModelId) ?? _availableModels.first;
  }

  // Set the selected model
  void setSelectedModel(String modelId) {
    _selectedModelId = modelId;
    debugPrint("Selected model changed to: $modelId");
  }

  // Legacy compatibility methods - now use the same selected model
  ChatModelConfig get visionModel => selectedModel;
  ChatModelConfig get presentationModel => selectedModel;
  ChatModelConfig get thinkingModeModel => selectedModel;

  // API endpoints
  String get apiBaseUrl => _apiBaseUrl;
  String get apiKey => _apiKey;

  // Search API configuration (placeholder - update with actual keys)
  String get braveSearchApiKey => 'your-brave-search-key';
  String get braveSearchUrl => 'https://api.search.brave.com/res/v1/web/search';
  
  // Image generation configuration
  Map<String, dynamic> get imageGenerationConfig => {
    'default_model_id': 'dall-e-3',
    'api_url': 'https://api.openai.com/v1/images/generations',
    'api_key': 'your-image-api-key'
  };
  String get defaultImageModelId => imageGenerationConfig['default_model_id'] ?? 'dall-e-3';
}

class ChatModelConfig {
  final String displayName;
  final String modelId;
  final String provider;
  final String type;
  final String status;
  final String description;
  final String? apiKey;
  final String? apiUrl;

  ChatModelConfig({
    required this.displayName,
    required this.modelId,
    required this.provider,
    required this.type,
    required this.status,
    required this.description,
    this.apiKey,
    this.apiUrl,
  });

  factory ChatModelConfig.fromJson(Map<String, dynamic> json) {
    return ChatModelConfig(
      displayName: json['displayName'] ?? json['id'] ?? 'Unknown Model',
      modelId: json['modelId'] ?? json['id'] ?? 'gpt-4o-mini',
      provider: json['provider'] ?? 'ahamai',
      type: json['type'] ?? 'chat',
      status: json['status'] ?? 'active',
      description: json['description'] ?? 'AI Model',
      apiKey: json['apiKey'],
      apiUrl: json['apiUrl'],
    );
  }
}

class ImageModelConfig {
  final String displayName;
  final String modelId;
  final String provider;

  ImageModelConfig({required this.displayName, required this.modelId, required this.provider});

  factory ImageModelConfig.fromJson(Map<String, dynamic> json) {
    return ImageModelConfig(
      displayName: json['displayName'] ?? json['id'] ?? 'Unknown Model',
      modelId: json['modelId'] ?? json['id'] ?? 'dall-e-3',
      provider: json['provider'] ?? 'openai',
    );
  }
}

class ImageApi {
  static Map<String, dynamic> get _config => ApiConfigService.instance.imageGenerationConfig;

  static Future<List<ImageModelConfig>> fetchModels() async {
    try {
      // Return a simple list of available image models
      return [
        ImageModelConfig(
          displayName: 'DALL-E 3',
          modelId: 'dall-e-3',
          provider: 'openai',
        ),
        ImageModelConfig(
          displayName: 'DALL-E 2',
          modelId: 'dall-e-2',
          provider: 'openai',
        ),
      ];
    } catch (e) {
      debugPrint("Error fetching image models: $e");
      return [];
    }
  }

  static Future<String?> generateImage({
    required String prompt,
    required String modelId,
    String size = "1024x1024",
    int n = 1,
  }) async {
    try {
      final apiUrl = _config['api_url'] ?? 'https://api.openai.com/v1/images/generations';
      final apiKey = _config['api_key'] ?? 'your-image-api-key';

      final requestData = {
        "prompt": prompt,
        "model": modelId,
        "n": n,
        "size": size,
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final imageUrl = responseData['data']?[0]?['url'];
        return imageUrl;
      } else {
        debugPrint("Image generation error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Error in generateImage: $e");
      return null;
    }
  }
}