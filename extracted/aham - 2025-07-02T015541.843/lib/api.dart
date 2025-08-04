import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiConfigService {
  ApiConfigService._privateConstructor();
  static final ApiConfigService instance = ApiConfigService._privateConstructor();

  Map<String, dynamic>? _config;
  bool _isInitialized = false;

  // FIX: Added a public getter for the initialization status
  bool get isInitialized => _isInitialized;

  static const String _obfuscatedUrl = 'aHR0cHM6Ly9naXN0LmdpdGh1YnVzZXJjb250ZW50LmNvbS9vZmZpY2lhbHByYWthc2hrdW1hcnNpbmdoL2IxZTU0MTdjMjZjN2M2OTQ4MzU1ODkzYzBkNDc2MGM1L3Jhdy9haGFtLWFwaS5qc29u';

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final url = utf8.decode(base64.decode(_obfuscatedUrl));
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        _config = jsonDecode(response.body);
        _isInitialized = true;
        debugPrint("API configuration loaded successfully.");
      } else {
        throw Exception('Failed to load remote API config: Status code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("FATAL: Could not initialize ApiConfigService. $e");
      throw Exception('Could not fetch app configuration. Please check your internet connection and restart the app.');
    }
  }

  String get defaultModelId {
    if (!_isInitialized) return 'gemini-2.5-flash';
    return _config!['default_model_id'] ?? 'gemini-2.5-flash';
  }

  List<ChatModelConfig> get chatModels {
    if (!_isInitialized) return [];
    final List<dynamic> models = _config!['chat_models'];
    return models.map((json) => ChatModelConfig.fromJson(json, _config!)).toList();
  }

  ChatModelConfig? getModelConfigById(String modelId) {
    return chatModels.firstWhere((m) => m.modelId == modelId, orElse: () => chatModels.first);
  }

  SpecialModelConfig get visionModel => SpecialModelConfig.fromJson(_config!['special_models']['vision'], _config!);
  SpecialModelConfig get presentationModel => SpecialModelConfig.fromJson(_config!['special_models']['presentation'], _config!);
  SpecialModelConfig get thinkingModeModel => SpecialModelConfig.fromJson(_config!['special_models']['thinking_mode'], _config!);

  String get braveSearchApiKey => _config!['other_apis']['brave_search']['apiKey'];
  String get braveSearchUrl => _config!['other_apis']['brave_search']['apiUrl'];
  Map<String, dynamic> get imageGenerationConfig => _config!['other_apis']['image_generation'];
  String get defaultImageModelId => imageGenerationConfig['default_model_id'] ?? '';
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

  factory ChatModelConfig.fromJson(Map<String, dynamic> json, Map<String, dynamic> fullConfig) {
    String providerKey = json['provider'];
    String? apiKey = fullConfig['api_providers'][providerKey]?['apiKey'];

    return ChatModelConfig(
      displayName: json['displayName'],
      modelId: json['modelId'],
      provider: providerKey,
      type: json['type'],
      status: json['status'],
      description: json['description'] ?? '',
      apiKey: apiKey,
      apiUrl: json['apiUrl'],
    );
  }
}

class SpecialModelConfig {
  final String modelId;
  final String provider;
  final String? type;
  final String? apiKey;
  final String? apiUrl;

  SpecialModelConfig({
    required this.modelId,
    required this.provider,
    this.type,
    this.apiKey,
    this.apiUrl,
  });

  factory SpecialModelConfig.fromJson(Map<String, dynamic> json, Map<String, dynamic> fullConfig) {
    String providerKey = json['provider'];
    String? apiKey = fullConfig['api_providers'][providerKey]?['apiKey'];

    return SpecialModelConfig(
      modelId: json['modelId'],
      provider: providerKey,
      type: json['type'],
      apiKey: apiKey,
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
      displayName: json['displayName'],
      modelId: json['modelId'],
      provider: json['provider'],
    );
  }
}

class ImageApi {
  static Map<String, dynamic> get _config => ApiConfigService.instance.imageGenerationConfig;
  static Map<String, dynamic>? get _fullConfig => ApiConfigService.instance._config;


  static Future<List<ImageModelConfig>> fetchModels() async {
    try {
      final List<dynamic> modelsJson = _config['models'];
      return modelsJson
        .where((m) => m['visible'] == true)
        .map((m) => ImageModelConfig.fromJson(m))
        .toList();
    } catch (e) {
      debugPrint("Error fetching image models: $e");
      return [];
    }
  }

  static Future<String> generateImage(String prompt, String modelId) async {
    final List<dynamic> models = _config['models'];
    final modelConfig = models.firstWhere((m) => m['modelId'] == modelId, orElse: () => null);

    if (modelConfig == null) {
      throw Exception("Model $modelId not found in config.");
    }

    final String provider = modelConfig['provider'];

    if (provider == 'pollinations') {
      final baseUrl = _config['providers']['pollinations']['baseUrl'];
      final encodedPrompt = Uri.encodeComponent(prompt);
      var url = '$baseUrl/prompt/$encodedPrompt?nologo=true&width=512&height=512';
      if (modelId != 'flux') {
        url += '&model=${Uri.encodeComponent(modelId)}';
      }
      return url;
    } else if (provider == 'infip') {
      final providerConfig = _config['providers']['infip'];
      final apiUrl = providerConfig['apiUrl'];
      final apiKey = _fullConfig!['api_providers']['infip']['apiKey'];

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'model': modelId,
          'prompt': prompt,
          'n': 1,
          'response_format': 'url',
          'size': '1024x1024',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'][0]['url'];
      } else {
        throw Exception('Failed to generate image with infip: ${response.statusCode} ${response.body}');
      }
    } else {
      throw Exception("Unsupported image provider: $provider");
    }
  }
}