import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The data class remains the same, it's a good structure.
class DeployedSite {
  final String siteId;
  final String url;
  final String name;
  final int timestamp;

  DeployedSite({required this.siteId, required this.url, required this.name, required this.timestamp});
}

class NetlifyDeployer {
  static const String _apiToken = 'nfp_mrE83gkp1y7jM9KJ3gvDYWnXKsqgSZh76025';
  static const String _apiUrl = 'https://api.netlify.com/api/v1';
  static final _client = Supabase.instance.client;

  // --- Site Management with Supabase ---

  static Future<void> _saveSite(DeployedSite newSite, String userId) async {
    await _client.from('deployed_sites').insert({
      'user_id': userId,
      'site_id': newSite.siteId,
      'url': newSite.url,
      'name': newSite.name,
    });
  }

  static Future<List<DeployedSite>> getDeployedSites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('deployed_sites')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response.map((item) => DeployedSite(
      siteId: item['site_id'],
      url: item['url'],
      name: item['name'],
      timestamp: DateTime.parse(item['created_at']).millisecondsSinceEpoch,
    )).toList();
  }

  // --- Deployment Logic ---

  static Future<DeployedSite> deployNewWebsite(File zipFile) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in.');

    final headers = {'Authorization': 'Bearer $_apiToken', 'Content-Type': 'application/json'};
    final createSiteResponse = await http.post(
      Uri.parse('$_apiUrl/sites'),
      headers: headers,
      body: jsonEncode({}),
    );

    if (createSiteResponse.statusCode != 201) {
      throw Exception('Failed to create Netlify site. Status: ${createSiteResponse.statusCode}, Body: ${createSiteResponse.body}');
    }

    final siteData = jsonDecode(createSiteResponse.body);
    final siteId = siteData['id'];
    final siteName = siteData['name'];
    if (siteId == null) throw Exception('Could not get site_id from Netlify.');

    final deployedUrl = await _uploadZip(siteId, zipFile);
    
    final newSite = DeployedSite(
      siteId: siteId, 
      url: deployedUrl, 
      name: siteName, 
      timestamp: DateTime.now().millisecondsSinceEpoch
    );
    await _saveSite(newSite, userId);
    return newSite;
  }

  static Future<String> redeployWebsite(String siteId, File zipFile) async {
    return await _uploadZip(siteId, zipFile);
  }
  
  // FIX: This function has been updated to poll for deployment status.
  static Future<String> _uploadZip(String siteId, File zipFile) async {
    final zipBytes = await zipFile.readAsBytes();
    final deployHeaders = {'Authorization': 'Bearer $_apiToken', 'Content-Type': 'application/zip'};

    final deployResponse = await http.post(
      Uri.parse('$_apiUrl/sites/$siteId/deploys'),
      headers: deployHeaders,
      body: zipBytes,
    );

    if (deployResponse.statusCode != 200) {
      throw Exception('Failed to deploy to Netlify. Status: ${deployResponse.statusCode}, Body: ${deployResponse.body}');
    }

    final deployData = jsonDecode(deployResponse.body);
    final deployId = deployData['id'];
    
    // Poll for the deployment to become ready
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(minutes: 2)) {
      final statusResponse = await http.get(
        Uri.parse('$_apiUrl/sites/$siteId/deploys/$deployId'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      );

      if (statusResponse.statusCode == 200) {
        final statusData = jsonDecode(statusResponse.body);
        final state = statusData['state'];
        
        if (state == 'ready') {
          final siteUrl = statusData['ssl_url'];
          if (siteUrl == null) throw Exception('Deployment is ready, but could not retrieve the site URL.');
          return siteUrl;
        } else if (state == 'error') {
           throw Exception('Netlify deployment failed with error state. Message: ${statusData['error_message']}');
        }
      }
      // Wait for 2 seconds before checking again
      await Future.delayed(const Duration(seconds: 2));
    }

    throw Exception('Deployment timed out after 2 minutes.');
  }
}