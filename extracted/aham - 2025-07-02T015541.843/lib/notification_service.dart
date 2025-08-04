import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationModel {
  final int id;
  final String title;
  final String message;
  final String type;
  final DateTime timestamp;
  final String? actionUrl;
  final String? imageUrl; // <<< ADDED: To support images in notifications
  bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.actionUrl,
    this.imageUrl, // <<< ADDED
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      title: json['title'] ?? 'No Title',
      message: json['message'] ?? 'No message content.',
      type: json['type'] ?? 'info',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      actionUrl: json['actionUrl'],
      imageUrl: json['imageUrl'], // <<< ADDED: Parsing the new field from JSON
    );
  }
}

class NotificationService {
  static const String _notificationUrl = 'https://gist.githubusercontent.com/officialprakashkumarsingh/7809c3587e9122792695f2b9b6888abb/raw/aham-notifications.json';
  static const String _readNotificationsKey = 'read_notification_ids';

  static Future<List<NotificationModel>> fetchNotifications() async {
    try {
      final response = await http.get(Uri.parse(_notificationUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> notificationList = data['notifications'];
        final notifications = notificationList.map((json) => NotificationModel.fromJson(json)).toList();
        
        // Sort by newest first
        notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return await _updateReadStatus(notifications);
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching notifications: $e");
      }
    }
    return [];
  }

  static Future<List<NotificationModel>> _updateReadStatus(List<NotificationModel> notifications) async {
    final prefs = await SharedPreferences.getInstance();
    final readIds = prefs.getStringList(_readNotificationsKey)?.map(int.parse).toSet() ?? {};
    for (var notification in notifications) {
      if (readIds.contains(notification.id)) {
        notification.isRead = true;
      }
    }
    return notifications;
  }
  
  static Future<void> markAsRead(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final readIds = prefs.getStringList(_readNotificationsKey) ?? [];
    if (!readIds.contains(id.toString())) {
      readIds.add(id.toString());
      await prefs.setStringList(_readNotificationsKey, readIds);
    }
  }

  static Future<void> markAllAsRead(List<NotificationModel> notifications) async {
    final prefs = await SharedPreferences.getInstance();
    final allIds = notifications.map((n) => n.id.toString()).toList();
    await prefs.setStringList(_readNotificationsKey, allIds);
  }

  static bool hasUnread(List<NotificationModel> notifications) {
    return notifications.any((n) => !n.isRead);
  }
}