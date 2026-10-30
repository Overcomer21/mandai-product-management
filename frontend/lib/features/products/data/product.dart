/// Explicit API DTOs: the widget tree never handles untyped JSON maps.
typedef JsonObject = Map<String, dynamic>;

JsonObject requireJsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Expected JSON object');
}

String requiredString(JsonObject json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Invalid string field: $key');
}

int requiredInt(JsonObject json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid integer field: $key');
}

bool requiredBool(JsonObject json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Invalid boolean field: $key');
}

String optionalString(JsonObject json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is String) return value;
  throw FormatException('Invalid string field: $key');
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.role});
  final String accessToken;
  final String role;

  factory AuthSession.fromJson(JsonObject json) => AuthSession(
        accessToken: requiredString(json, 'access_token'),
        role: requiredString(json, 'role'),
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stock,
    required this.isActive,
    this.imageUrl = '',
    this.spinImageUrls = '',
  });

  final int id;
  final String name;
  final String description;
  final String category;

  /// Exact decimal text from JSON (not a floating-point calculation).
  final String price;
  final int stock;
  final bool isActive;
  final String imageUrl;
  final String spinImageUrls;

  List<String> get spinFrames => spinImageUrls
      .split(RegExp(r'\r?\n'))
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);

  factory Product.fromJson(JsonObject json) {
    final rawPrice = json['price'];
    if (rawPrice is! String && rawPrice is! num) {
      throw const FormatException('Invalid product price');
    }
    final priceText = rawPrice.toString();
    if (num.tryParse(priceText) == null) {
      throw const FormatException('Invalid product price');
    }
    return Product(
      id: requiredInt(json, 'id'),
      name: requiredString(json, 'name'),
      description: requiredString(json, 'description'),
      category: requiredString(json, 'category'),
      price: priceText,
      stock: requiredInt(json, 'stock'),
      isActive: requiredBool(json, 'is_active'),
      imageUrl: optionalString(json, 'image_url'),
      spinImageUrls: optionalString(json, 'spin_image_urls'),
    );
  }
}

class PurchaseResult {
  const PurchaseResult({required this.orderId, required this.status});
  final int orderId;
  final String status;

  factory PurchaseResult.fromJson(JsonObject json) => PurchaseResult(
        orderId: requiredInt(json, 'order_id'),
        status: requiredString(json, 'status'),
      );
}
