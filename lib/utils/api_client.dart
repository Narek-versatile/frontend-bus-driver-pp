import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  // Standard Android emulator localhost URL. Replace with your actual server URL.
  static const String baseUrl = 'http://10.0.2.2:3000/api';
  static const _storage = FlutterSecureStorage();

  static Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  static Future<void> clearAuth() async {
    await _storage.deleteAll();
  }

  static Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Bypass-Tunnel-Reminder': 'true',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    dynamic decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = {'error': 'Network tunnel unreachable (Status: ${response.statusCode})'};
    }
    return { 'statusCode': response.statusCode, 'body': decodedBody };
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Bypass-Tunnel-Reminder': 'true',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    dynamic decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } catch (_) {
      decodedBody = {'error': 'Network tunnel unreachable (Status: ${response.statusCode})'};
    }
    return { 'statusCode': response.statusCode, 'body': decodedBody };
  }
}
