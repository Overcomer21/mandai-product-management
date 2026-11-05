import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ??
            const String.fromEnvironment('API_BASE',
                defaultValue: 'http://localhost:8000');
  final http.Client _client;
  final String baseUrl;
  String? accessToken;

  Future<Object?> request(String method, String path,
      {Object? data, String? idempotencyKey}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
    final body = data == null ? null : jsonEncode(data);
    final http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await _client.post(uri, headers: headers, body: body);
          break;
        case 'PUT':
          response = await _client.put(uri, headers: headers, body: body);
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
          break;
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        default:
          throw ArgumentError.value(method, 'method');
      }
    } on http.ClientException catch (error) {
      throw ApiException(0, 'Network error: $error');
    }
    Object? payload;
    try {
      payload = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(response.statusCode, 'Invalid server response');
    }
    if (response.statusCode >= 400) {
      final detail = payload is Map<String, dynamic> ? payload['detail'] : null;
      throw ApiException(response.statusCode,
          detail?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return payload;
  }

  void close() => _client.close();
}
