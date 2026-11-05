part of '../main.dart';

class Api {
  String? token;
  String? role;
  Map<String, String> headers({String? key}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (key != null) 'Idempotency-Key': key,
      };
  Future<dynamic> request(String method, String path,
      {Object? data, String? key}) async {
    final uri = Uri.parse('$apiBase$path');
    final body = data == null ? null : jsonEncode(data);
    late http.Response res;
    if (method == 'POST') {
      res = await http.post(uri, headers: headers(key: key), body: body);
    } else if (method == 'PUT') {
      res = await http.put(uri, headers: headers(key: key), body: body);
    } else if (method == 'DELETE') {
      res = await http.delete(uri, headers: headers(key: key));
    } else {
      res = await http.get(uri, headers: headers(key: key));
    }
    dynamic result;
    final responseText = res.body.trim();
    if (responseText.isNotEmpty) {
      try {
        result = jsonDecode(responseText);
      } on FormatException {
        if (res.statusCode >= 400) {
          throw Exception('HTTP ${res.statusCode} ${res.reasonPhrase ?? ''}: '
              '${responseText.length > 300 ? responseText.substring(0, 300) : responseText}');
        }
        throw FormatException(
            'API returned non-JSON response (HTTP ${res.statusCode})');
      }
    }
    if (res.statusCode >= 400) {
      final detail = result is Map ? result['detail'] : null;
      throw Exception(
          'HTTP ${res.statusCode}: ${detail ?? res.reasonPhrase ?? 'Request failed'}');
    }
    return result;
  }

  Future<void> login(String email, String password) async {
    final data = await request('POST', '/api/auth/login',
        data: {'email': email, 'password': password});
    token = data['access_token'];
    role = data['role'];
  }
}
