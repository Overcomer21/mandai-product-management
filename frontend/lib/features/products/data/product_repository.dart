import '../../../core/network/api_client.dart';
import 'product.dart';

class ProductRepository {
  const ProductRepository(this._api);
  final ApiClient _api;
  Future<List<Product>> list({required bool admin}) async {
    final response = await _api.request(
        'GET', admin ? '/api/admin/products' : '/api/products');
    if (response is! List) {
      throw const FormatException('Expected a product list');
    }
    return List<Product>.unmodifiable(
        response.map((item) => Product.fromJson(requireJsonObject(item))));
  }

  Future<void> save(ProductInput input, {int? id}) async {
    await _api.request(id == null ? 'POST' : 'PUT',
        id == null ? '/api/admin/products' : '/api/admin/products/$id',
        data: input.toJson());
  }

  Future<void> delete(int id) async {
    await _api.request('DELETE', '/api/admin/products/$id');
  }
}

class ProductInput {
  const ProductInput(
      {required this.name,
      required this.category,
      required this.description,
      required this.price,
      required this.stock,
      required this.isActive,
      this.imageUrl = '',
      this.spinImageUrls = ''});
  final String name, category, description, price;
  final int stock;
  final bool isActive;
  final String imageUrl, spinImageUrls;
  Map<String, Object> toJson() => {
        'name': name,
        'category': category,
        'description': description,
        'price': price,
        'stock': stock,
        'is_active': isActive,
        'image_url': imageUrl,
        'spin_image_urls': spinImageUrls
      };
}
