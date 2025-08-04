import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse; // NEW: Import for advanced HTML parsing
import 'api.dart';

// --- BRAVE SEARCH MODELS AND SERVICE (UNCHANGED) ---

class SearchResult {
  final String title;
  final String url;
  final String? faviconUrl;

  SearchResult({required this.title, required this.url, this.faviconUrl});

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'faviconUrl': faviconUrl,
  };

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    title: json['title'],
    url: json['url'],
    faviconUrl: json['faviconUrl'],
  );
}

class WebSearchResponse {
  final String promptContent;
  final List<SearchResult> results;

  WebSearchResponse({required this.promptContent, required this.results});
}

class WebSearchService {
  static Future<WebSearchResponse?> search(String query) async {
    final apiUrl = ApiConfigService.instance.braveSearchUrl;
    final apiKey = ApiConfigService.instance.braveSearchApiKey;

    final uri = Uri.parse('$apiUrl?q=${Uri.encodeComponent(query)}&count=20');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic>? resultsJson = decodedResponse['web']?['results'];

        if (resultsJson == null || resultsJson.isEmpty) return null;

        final searchResults = resultsJson.map((r) {
          return SearchResult(
            title: r['title'] ?? 'Untitled',
            url: r['url'] ?? '',
            faviconUrl: r['profile']?['img'],
          );
        }).toList();
        
        final StringBuffer formattedResults = StringBuffer();
        formattedResults.writeln("Here are the top web search results for '$query':");
        
        for (var i = 0; i < searchResults.length; i++) {
          final result = searchResults[i];
          final snippet = resultsJson[i]['description'] ?? 'No snippet available.';
          formattedResults.writeln('\n${i + 1}. Title: ${result.title}');
          formattedResults.writeln('   URL: ${result.url}');
          formattedResults.writeln('   Snippet: $snippet');
        }
        
        return WebSearchResponse(
          promptContent: formattedResults.toString(),
          results: searchResults
        );
      } else {
        print('Brave Search API Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error during web search: $e');
      return null;
    }
  }
}

// MODIFIED: Increased summary depth
class WikipediaSearchService {
  static const String _apiUrl = "https://en.wikipedia.org/w/api.php";

  static Future<String?> search(String query) async {
    try {
      final searchUri = Uri.parse('$_apiUrl?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&utf8=');
      final searchResponse = await http.get(searchUri);
      
      if (searchResponse.statusCode != 200) {
        print('Wikipedia Search API Error: ${searchResponse.statusCode}');
        return "Failed to contact Wikipedia's search API.";
      }

      final searchData = jsonDecode(searchResponse.body);
      final searchResults = searchData['query']?['search'] as List<dynamic>?;

      if (searchResults == null || searchResults.isEmpty) {
        return "No Wikipedia article found for '$query'.";
      }

      final String pageTitle = searchResults[0]['title'];

      final extractUri = Uri.parse('$_apiUrl?action=query&prop=extracts&exintro&explaintext&titles=${Uri.encodeComponent(pageTitle)}&format=json&utf8=');
      final extractResponse = await http.get(extractUri);

      if (extractResponse.statusCode != 200) {
         return "Could not fetch details for the article on '$pageTitle'.";
      }

      final extractData = jsonDecode(extractResponse.body);
      final pages = extractData['query']?['pages'] as Map<String, dynamic>?;

      if (pages == null || pages.isEmpty) return null;

      final pageData = pages.values.first;
      final String extract = pageData['extract'] ?? "Could not find a summary for the article on '$pageTitle'.";
      
      // Increased depth from 2000 to 4000 characters
      return extract.length > 4000 ? '${extract.substring(0, 4000)}...' : extract;
    } catch (e) {
      print("Error during Wikipedia search: $e");
      return "An error occurred while searching Wikipedia.";
    }
  }
}

// MODIFIED: Upgraded to use a proper HTML parser and a User-Agent
class UrlScraperService {
  static Future<String?> scrape(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          // Add a user-agent to appear more like a regular browser
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
      );

      if (response.statusCode == 200) {
        // Use the html package to parse the document
        final document = parse(response.body);
        
        // Extract text only from the body, which is cleaner than regex
        String? text = document.body?.text;
        
        if (text == null || text.trim().isEmpty) {
          return "Failed to extract any readable text from the URL.";
        }

        // Remove excessive whitespace and newlines for a cleaner output
        text = text.replaceAll(RegExp(r'\s{2,}',), ' ').trim();
        
        // Truncate to a reasonable length for the context window
        return text.length > 5000 ? '${text.substring(0, 5000)}...' : text;
      } else {
        return "Failed to access URL. Server responded with status code: ${response.statusCode}";
      }
    } catch (e) {
      print("URL Scraping Error: $e");
      return "An error occurred while trying to scrape the URL. Please ensure it is valid and accessible.";
    }
  }
}