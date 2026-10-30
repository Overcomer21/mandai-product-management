import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Navigation hint only. Never treat success/cancel query parameter as payment proof.
class PaymentReturnLinks {
  PaymentReturnLinks(this.onReturn);
  final Future<void> Function(String sessionId) onReturn;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  final Set<String> _active = {};

  void start() {
    if (kIsWeb) {
      _consume(Uri.base);
    } else {
      _sub = _appLinks.uriLinkStream.listen(_consume, onError: (Object _) {});
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) _consume(uri);
      }).catchError((Object _) {});
    }
  }

  void _consume(Uri uri) {
    final isCustom =
        uri.scheme == 'mandai-merchandise' && uri.host == 'payment-return';
    final isWebReturn = kIsWeb &&
        uri.queryParameters['session_id'] != null &&
        uri.queryParameters.containsKey('result');
    if (!isCustom && !isWebReturn) return;
    final id = uri.queryParameters['session_id'] ?? '';
    if (!RegExp(r'^cs_test_[A-Za-z0-9_]{8,255}$').hasMatch(id)) return;
    if (!_active.add(id)) return;
    onReturn(id).whenComplete(() => _active.remove(id));
  }

  void dispose() => _sub?.cancel();
}
