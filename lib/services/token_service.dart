import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenService {
  // Secure Storage Object
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Save Access Token
  Future<void> savetoken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  // Get Access Token
  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  // Save Refresh Token
  Future<void> saveRefreshToken(String refreshToken) async {
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  // Get Refresh Token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: 'refresh_token');
  }

  // Delete Access Token
  Future<void> deleteToken() async {
    await _storage.delete(key: 'auth_token');
  }

  // Delete Both Tokens (Logout)
  Future<void> deleteAllTokens() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'refresh_token');
  }
}
