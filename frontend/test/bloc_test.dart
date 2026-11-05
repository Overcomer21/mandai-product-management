import 'package:flutter_test/flutter_test.dart';
import 'package:mandai_merchandise/features/auth/bloc/auth_bloc.dart';
import 'package:mandai_merchandise/features/products/bloc/product_bloc.dart';
import 'package:mandai_merchandise/features/purchases/bloc/purchase_bloc.dart';

void main() {
  test('Auth events use typed credentials', () {
    const e = SignInRequested('x', 'y');
    expect(e.email, 'x');
  });
  test('Product state starts empty', () {
    const s = ProductState();
    expect(s.products, isEmpty);
  });
  test('Purchase state defaults to idle', () {
    const s = PurchaseState();
    expect(s.status, PurchaseStatus.idle);
  });
}
