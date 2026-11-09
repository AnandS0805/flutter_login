import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_service.dart';

class AuthService {
  static const String baseUrl = 'http://192.168.1.131:3000';

  // All API requests ka timeout
  static const Duration requestTimeout = Duration(seconds: 15);

  // ================= REGISTER API =================

  Future<http.Response> registerUser({
    required String name,
    required String email,
    required String mobile,
    required String password,
    required String confirmPassword,
  }) async {
    final url = Uri.parse('$baseUrl/register');

    print('Registration API Request Started');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'mobile': mobile,
            'password': password,
            'confirmPassword': confirmPassword,
          }),
        )
        .timeout(requestTimeout);

    print('Registration API Status: ${response.statusCode}');

    return response;
  }

  // ================= LOGIN API =================

  Future<http.Response> userLogin({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/login');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(requestTimeout);

    print('Login API Status: ${response.statusCode}');

    return response;
  }

  // ================= PROFILE API =================

  Future<http.Response> getUserProfile({required String token}) async {
    final url = Uri.parse('$baseUrl/profile');

    // First Profile API Call
    var response = await http
        .get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(requestTimeout);

    // Check Access Token Expired
    if (response.statusCode == 401) {
      print('Access Token Expired - Refreshing Token');

      // Refresh Token API Call
      final refreshResponse = await refreshWithSavedToken();

      if (refreshResponse != null && refreshResponse.statusCode == 200) {
        final tokenService = TokenService();

        // Get New Access Token
        final newToken = await tokenService.getToken();

        if (newToken != null && newToken.isNotEmpty) {
          print('Refresh Successful');
          print('Retrying Original API Request');

          // Retry Profile API with New Token
          response = await http
              .get(
                url,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $newToken',
                },
              )
              .timeout(requestTimeout);
        }
      } else {
        print('Refresh Failed');
      }
    }

    print('Profile API Response: ${response.body}');

    return response;
  }

  // ================= REFRESH API =================

  Future<http.Response> refreshAccessToken({
    required String refreshToken,
  }) async {
    final url = Uri.parse('$baseUrl/refresh');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(requestTimeout);

    print('Refresh API Response: ${response.body}');

    return response;
  }

  // ================= REFRESH USING SAVED TOKEN =================

  Future<http.Response?> refreshWithSavedToken() async {
    final tokenService = TokenService();

    // Get Saved Refresh Token
    final refreshToken = await tokenService.getRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      print('Refresh Token Not Found');

      await tokenService.deleteAllTokens();

      return null;
    }

    // Call Refresh API
    final response = await refreshAccessToken(refreshToken: refreshToken);

    // Check Refresh API Response
    if (response.statusCode != 200) {
      print('Refresh Failed: ${response.statusCode}');

      // Delete tokens only when Refresh Token is invalid
      if (response.statusCode == 401 || response.statusCode == 403) {
        await tokenService.deleteAllTokens();
      }

      // Server errors do not delete tokens
      return response;
    }

    try {
      final responseData = jsonDecode(response.body);

      final newAccessToken = responseData['accessToken'];

      if (newAccessToken is String && newAccessToken.isNotEmpty) {
        // Save New Access Token
        await tokenService.savetoken(newAccessToken);

        print('New Access Token Saved Successfully');

        return response;
      }

      throw FormatException('Access Token Missing');
    } catch (e) {
      print('Invalid Refresh Response: $e');

      await tokenService.deleteAllTokens();

      return response;
    }
  }
}
