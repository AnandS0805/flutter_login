import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'token_service.dart';
import 'auth_service.dart';

class ApiClient {
  final TokenService _tokenService = TokenService();
  final AuthService _authService = AuthService();

  // All API requests ke liye maximum waiting time
  static const Duration requestTimeout = Duration(seconds: 15);

  Future<http.Response> _sendRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
  }) async {
    // Get current Access Token
    final token = await _tokenService.getToken();

    if (token == null || token.isEmpty) {
      throw Exception('Access Token Not Found');
    }

    // Create complete API URL
    final url = Uri.parse('${AuthService.baseUrl}$endpoint');

    // Common HTTP request function
    Future<http.Response> sendRequest(String accessToken) {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      switch (method) {
        case 'GET':
          return http.get(url, headers: headers).timeout(requestTimeout);

        case 'POST':
          return http
              .post(url, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(requestTimeout);

        case 'PUT':
          return http
              .put(url, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(requestTimeout);

        case 'DELETE':
          return http.delete(url, headers: headers).timeout(requestTimeout);

        default:
          throw Exception('Invalid HTTP Method: $method');
      }
    }

    // First API request
    var response = await sendRequest(token);

    // Check Access Token expiration
    if (response.statusCode == 401) {
      debugPrint('Access Token Expired - Refreshing Token');

      final refreshResponse = await _authService.refreshWithSavedToken();

      if (refreshResponse != null && refreshResponse.statusCode == 200) {
        debugPrint('Refresh Successful');

        // Get newly saved Access Token
        final newToken = await _tokenService.getToken();

        if (newToken != null && newToken.isNotEmpty) {
          debugPrint('Retrying Original API Request');

          // Retry original API request with new token
          response = await sendRequest(newToken);
        }
      } else {
        debugPrint('Token Refresh Failed');

        // Server error ko original 401 ki jagah return karo
        if (refreshResponse != null && refreshResponse.statusCode >= 500) {
          response = refreshResponse;
        }
      }
    }

    // Return final API response
    return response;
  }

  // GET Request
  Future<http.Response> get(String endpoint) {
    return _sendRequest(method: 'GET', endpoint: endpoint);
  }

  // POST Request
  Future<http.Response> post(
    String endpoint, {
    required Map<String, dynamic> body,
  }) {
    return _sendRequest(method: 'POST', endpoint: endpoint, body: body);
  }

  // PUT Request
  Future<http.Response> put(
    String endpoint, {
    required Map<String, dynamic> body,
  }) {
    return _sendRequest(method: 'PUT', endpoint: endpoint, body: body);
  }

  // DELETE Request
  Future<http.Response> delete(String endpoint) {
    return _sendRequest(method: 'DELETE', endpoint: endpoint);
  }
}
