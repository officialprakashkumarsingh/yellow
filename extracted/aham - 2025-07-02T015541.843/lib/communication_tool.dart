import 'package:url_launcher/url_launcher.dart';

class CommunicationService {
  
  static Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: to,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        return true;
      }
    } catch (e) {
      print('Error sending email: $e');
    }
    return false;
  }
  
  static Future<bool> sendWhatsApp({
    required String phone,
    required String message,
  }) async {
    // Clean the phone number to include country code without '+' or spaces
    final cleanedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final Uri whatsappUri = Uri.parse('https://wa.me/$cleanedPhone?text=${Uri.encodeComponent(message)}');

    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('Error sending WhatsApp message: $e');
    }
    return false;
  }
}