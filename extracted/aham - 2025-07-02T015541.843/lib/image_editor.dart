import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ImageEditingService {
  static const String _apiKey = 'infip-3f603047';
  static const String _endpoint = 'https://api.infip.pro/v1/images/edits';
  // As per the working cURL example you provided
  static const String _model = 'gpt-image-1';

  /// Determines the image size based on keywords in the prompt.
  /// The API supports '1024x1024', '1536x1024', '1024x1536'.
  static String _selectSize(String prompt) {
    final p = prompt.toLowerCase();
    if (p.contains('portrait')) {
      return '1024x1536';
    } else if (p.contains('landscape')) {
      return '1536x1024';
    }
    // Default to square if no specific orientation is requested.
    return '1024x1024';
  }

  /// Sends a request to the image editing API.
  ///
  /// Takes a text [prompt] and an [imageFile] to be edited.
  /// Returns the URL of the newly generated image.
  static Future<String> editImage({
    required String prompt,
    required XFile imageFile,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_endpoint));

      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.headers['Accept'] = 'application/json';

      final imageBytes = await imageFile.readAsBytes();

      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: imageFile.name,
      ));

      request.fields['prompt'] = prompt;
      request.fields['model'] = _model;
      request.fields['n'] = '1';
      request.fields['size'] = _selectSize(prompt);
      request.fields['response_format'] = 'url';

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          final imageUrl = data['data'][0]['url'];
          if (imageUrl != null) {
            return imageUrl;
          }
        }
        throw Exception('Image URL not found in API response.');
      } else {
        throw Exception('API Error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      // Rethrowing the exception so the UI layer can handle and display the error.
      rethrow;
    }
  }
}