import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Separate sandbox checkout client. Does not change the existing demo checkout.
class StripeCheckoutClient {
  const StripeCheckoutClient({required this.apiBase, required this.token});
  final String apiBase;
  final String token;

  Future<Map<String, dynamic>> _request(String method, String path,
      {Object? body, String? key}) async {
    final uri = Uri.parse('$apiBase$path');
    final response = method == 'POST'
        ? await http
            .post(uri,
                headers: {
                  'Authorization': 'Bearer $token',
                  if (body != null) 'Content-Type': 'application/json',
                  if (key != null) 'Idempotency-Key': key,
                },
                body: body == null ? null : jsonEncode(body))
            .timeout(const Duration(seconds: 25))
        : await http.get(uri, headers: {
            'Authorization': 'Bearer $token',
          }).timeout(const Duration(seconds: 25));
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw StateError(decoded is Map
          ? (decoded['detail'] ?? 'Payment request failed').toString()
          : 'Payment request failed (${response.statusCode})');
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid payment API response');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return 'stripe-${base64UrlEncode(bytes)}';
  }

  Future<Map<String, dynamic>> createSession({
    required List<Map<String, int>> items,
    required String deliveryAddress,
    required String idempotencyKey,
  }) =>
      _request('POST', '/api/stripe-checkout/sessions',
          key: idempotencyKey,
          body: {'items': items, 'delivery_address': deliveryAddress});

  Future<Map<String, dynamic>> orderForSession(String sessionId) => _request(
      'GET',
      '/api/stripe-checkout/return/session/${Uri.encodeComponent(sessionId)}');

  Future<Map<String, dynamic>> checkStatus(int orderId) =>
      _request('GET', '/api/stripe-checkout/orders/$orderId');

  Future<Map<String, dynamic>> reconcile(int orderId) =>
      _request('POST', '/api/stripe-checkout/orders/$orderId/reconcile');

  Future<Map<String, dynamic>> cancelOrder(int orderId) =>
      _request('POST', '/api/stripe-checkout/orders/$orderId/cancel');

  Future<Map<String, dynamic>> resume(int orderId) =>
      _request('GET', '/api/stripe-checkout/orders/$orderId/resume');

  Future<void> openStripe(String checkoutUrl) async {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'checkout.stripe.com' ||
            uri.host.endsWith('.checkout.stripe.com'))) {
      throw const FormatException('Invalid hosted Stripe Checkout URL');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Unable to open Stripe Checkout');
    }
  }
}
