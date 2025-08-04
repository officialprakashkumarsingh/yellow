import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SharingService {
  static Future<void> handleSharingRequest({
    required String prompt,
    required String generatedContent,
    required BuildContext context,
  }) async {
    final lowerCasePrompt = prompt.toLowerCase();
    
    // Check for WhatsApp sharing
    if (lowerCasePrompt.contains('whatsapp')) {
      _shareToWhatsApp(
        prompt: prompt, 
        content: generatedContent, 
        context: context
      );
      return;
    }

    // Check for Email sharing
    if (lowerCasePrompt.contains('email')) {
      _shareToEmail(
        prompt: prompt, 
        content: generatedContent, 
        context: context
      );
      return;
    }
  }

  static Future<void> _shareToWhatsApp({
    required String prompt, 
    required String content, 
    required BuildContext context
  }) async {
    final phoneRegex = RegExp(r'(\+?\d[\d -]{8,12}\d)');
    final match = phoneRegex.firstMatch(prompt);
    String? phoneNumber = match?.group(0)?.replaceAll(RegExp(r'[\s-]'), '');

    final text = 'Shared from AhamAI:\n\n*User Prompt:*\n$prompt\n\n*AI Response:*\n$content';
    final encodedText = Uri.encodeComponent(text);
    
    Uri? uri;
    if (phoneNumber != null) {
      // Direct message to a specific number
      uri = Uri.parse('https://wa.me/$phoneNumber?text=$encodedText');
    } else {
      // Open WhatsApp to let user choose a contact
      uri = Uri.parse('whatsapp://send?text=$encodedText');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch WhatsApp. Is it installed?')),
      );
    }
  }

  static Future<void> _shareToEmail({
    required String prompt, 
    required String content, 
    required BuildContext context
  }) async {
    final emailRegex = RegExp(r'([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z0-9_-]+)');
    final match = emailRegex.firstMatch(prompt);
    String? recipient = match?.group(0);

        final subject = 'Information shared from AhamAI';
    final body = '''
    Hello,

    Here is the information you requested from AhamAI:

---
User Prompt:
$prompt
---

AI Response:
$content
---
''';

    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    
    Uri uri;
    if (recipient != null) {
      uri = Uri.parse('mailto:$recipient?subject=$encodedSubject&body=$encodedBody');
    } else {
      uri = Uri.parse('mailto:?subject=$encodedSubject&body=$encodedBody');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open email client.')),
      );
    }
  }
}