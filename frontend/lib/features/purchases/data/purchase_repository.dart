import 'dart:convert';
import 'dart:math';
import '../../../core/network/api_client.dart';
import '../../products/data/product.dart';

class PurchaseRepository {
  const PurchaseRepository(this._api);
  final ApiClient _api;
  Future<PurchaseResult> buy(int productId, int quantity) async {
    final random = Random.secure();
    final nonce = List<int>.generate(16, (_) => random.nextInt(256));
    final key = 'purchase-${base64UrlEncode(nonce)}';
    final result = await _api.request('POST', '/api/purchases',
        idempotencyKey: key,
        data: {'product_id': productId, 'quantity': quantity});
    return PurchaseResult.fromJson(requireJsonObject(result));
  }
}
