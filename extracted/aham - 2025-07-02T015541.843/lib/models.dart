// lib/models.dart

import 'dart:typed_data';
import 'package:flutter/widgets.dart'; // Added for IconData
import 'package:ahamai/web_search.dart';

enum MessageType { 
  text, 
  image, 
  presentation, 
  file,
}

class ChatMessage {
  final String role;
  final String text;
  final String? thoughts;
  final MessageType type;
  final String? imageUrl;
  final List<String>? slides;
  final List<SearchResult>? searchResults;
  final Uint8List? imageBytes;
  final String? attachedFileName;
  final List<String>? attachedContainedFiles;
  final DateTime timestamp;
  final String? filePath;
  // NEW: Added statusIcon for agent UI
  final IconData? statusIcon;


  ChatMessage({
    required this.role,
    required this.text,
    this.thoughts,
    this.type = MessageType.text,
    this.imageUrl,
    this.slides,
    this.searchResults,
    this.imageBytes,
    this.attachedFileName,
    this.attachedContainedFiles,
    required this.timestamp,
    this.filePath,
    this.statusIcon, // NEW: Added to constructor
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'thoughts': thoughts,
    'type': type.name,
    'imageUrl': imageUrl,
    'slides': slides,
    'searchResults': searchResults?.map((r) => r.toJson()).toList(),
    'attachedFileName': attachedFileName,
    'attachedContainedFiles': attachedContainedFiles,
    'timestamp': timestamp.toIso8601String(),
    'filePath': filePath,
    // 'statusIcon' is a UI-only property and is not serialized to JSON
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
      role: json['role'],
      text: json['text'],
      thoughts: json['thoughts'],
      // Handle legacy messages that might not have a type
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text
      ),
      imageUrl: json['imageUrl'],
      slides: json['slides'] != null ? List<String>.from(json['slides']) : null,
      searchResults: json['searchResults'] != null ? (json['searchResults'] as List).map((r) => SearchResult.fromJson(r)).toList() : null,
      attachedFileName: json['attachedFileName'],
      attachedContainedFiles: json['attachedContainedFiles'] != null ? List<String>.from(json['attachedContainedFiles']) : null,
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      filePath: json['filePath'],
      // 'statusIcon' is not loaded from JSON
  );
}

class ChatInfo {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final bool isPinned;
  final bool isGenerating;
  final bool isStopped;
  final String category;

  ChatInfo({required this.id, required this.title, required this.messages, required this.isPinned, required this.isGenerating, required this.isStopped, required this.category});
  ChatInfo copyWith({String? id, String? title, List<ChatMessage>? messages, bool? isPinned, bool? isGenerating, bool? isStopped, String? category}) => ChatInfo(id: id ?? this.id, title: title ?? this.title, messages: messages ?? this.messages, isPinned: isPinned ?? this.isPinned, isGenerating: isGenerating ?? this.isGenerating, isStopped: isStopped ?? this.isStopped, category: category ?? this.category);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'messages': messages.map((m) => m.toJson()).toList(), 'isPinned': isPinned, 'isGenerating': isGenerating, 'isStopped': isStopped, 'category': category};
  factory ChatInfo.fromJson(Map<String, dynamic> json) => ChatInfo(id: json['id'], title: json['title'], messages: (json['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList(), isPinned: json['isPinned'] ?? false, isGenerating: json['isGenerating'] ?? false, isStopped: json['isStopped'] ?? false, category: json['category'] ?? 'General');
}