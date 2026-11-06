import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mandai_merchandise/core/network/api_client.dart';
import 'package:mandai_merchandise/features/auth/data/auth_repository.dart';
import 'package:mandai_merchandise/features/products/data/product_repository.dart';
import 'package:mandai_merchandise/features/purchases/data/purchase_repository.dart';

void main() {
  test('Q5 storefront uses public product API', () async {
    final api = ApiClient(client: MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/api/products');
      return http.Response(jsonEncode([{
        'id': 1, 'name': 'Panda Plush', 'description': '',
        'category': 'Plush', 'price': '20.00', 'stock': 5,
        'is_active': true
      }]), 200);
    }), baseUrl: 'http://localhost:8000');
    final products = await ProductRepository(api).list(admin: false);
    expect(products.single.name, 'Panda Plush');
    api.close();
  });

  test('Q5 admin inventory uses authenticated CRUD HTTP contract', () async {
    final calls = <String>[];
    final api = ApiClient(client: MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      expect(req.headers['Authorization'], 'Bearer q5-admin-token');
      if (req.method == 'GET') return http.Response('[]', 200);
      return http.Response('{}', 200);
    }), baseUrl: 'http://localhost:8000');
    api.accessToken = 'q5-admin-token';
    final repo = ProductRepository(api);
    expect(await repo.list(admin: true), isEmpty);
    await repo.save(const ProductInput(name: 'Q5', category: 'Tests',
      description: '', price: '7.00', stock: 1, isActive: true));
    await repo.save(const ProductInput(name: 'Q5', category: 'Tests',
      description: '', price: '7.00', stock: 2, isActive: true), id: 41);
    await repo.delete(41);
    expect(calls, ['GET /api/admin/products', 'POST /api/admin/products',
      'PUT /api/admin/products/41', 'DELETE /api/admin/products/41']);
    api.close();
  });

  test('Q5 sign-in and purchase send bearer token and unique idempotency key', () async {
    final api = ApiClient(client: MockClient((req) async {
      if (req.url.path == '/api/auth/login') {
        expect(req.method, 'POST');
        return http.Response('{"access_token":"q5-user-token","role":"user"}', 200);
      }
      expect(req.url.path, '/api/purchases');
      expect(req.headers['Authorization'], 'Bearer q5-user-token');
      final key = req.headers['Idempotency-Key'];
      expect(key, isNotNull);
      expect(key!.length, greaterThanOrEqualTo(8));
      expect(jsonDecode(req.body), {'product_id': 1, 'quantity': 1});
      return http.Response('{"order_id":42,"product_id":1,"quantity":1,"total_amount":"20.00","status":"completed","replayed":false}',201);
    }), baseUrl:'http://localhost:8000');
    await AuthRepository(api).signIn('user@test.local', 'secret');
    final result = await PurchaseRepository(api).buy(1, 1);
    expect(result.orderId, 42);
    api.close();
  });
}
