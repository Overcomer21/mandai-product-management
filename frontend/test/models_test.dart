import 'package:flutter_test/flutter_test.dart';
import 'package:mandai_merchandise/models.dart';

void main() {
  test('parses a typed Product from API data', () {
    final product = Product.fromJson(<String, dynamic>{
      'id': 10,
      'name': 'Panda Plush',
      'description': 'Demo item',
      'category': 'Gifts',
      'price': '29.90',
      'stock': 4,
      'is_active': true,
    });
    expect(product.id, 10);
    expect(product.price, '29.90');
    expect(product.stock, 4);
  });

  test('rejects incorrect server field types', () {
    expect(
        () => Product.fromJson(<String, dynamic>{
              'id': 'not-an-int',
              'name': 'Panda Plush',
              'description': '',
              'category': 'Gifts',
              'price': '29.90',
              'stock': 4,
              'is_active': true,
            }),
        throwsFormatException);
  });

  test('parses typed authentication and purchase responses', () {
    final session = AuthSession.fromJson(<String, dynamic>{
      'access_token': 'example-token',
      'role': 'admin',
    });
    final purchase = PurchaseResult.fromJson(<String, dynamic>{
      'order_id': 99,
      'status': 'completed',
    });
    expect(session.role, 'admin');
    expect(purchase.orderId, 99);
  });
}
