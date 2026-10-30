import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'widgets/store_widgets.dart';
import 'widgets/concurrency_test_page.dart';
import 'widgets/customer_account_panel.dart';
import 'widgets/mandai_splash_gate.dart';
import 'features/products/view/commerce_media_dialog.dart';
import 'features/payments/stripe_checkout_client.dart';
import 'features/payments/payment_return_links.dart';

const apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');
void main() => runApp(const MerchandiseApp());

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
      throw Exception('HTTP ${res.statusCode}: ${detail ?? res.reasonPhrase ?? 'Request failed'}');
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

class MerchandiseApp extends StatelessWidget {
  const MerchandiseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mandai Merchandise • Assessment',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F8F6),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF146C55),
            primary: const Color(0xFF146C55),
            secondary: const Color(0xFFB47B3D),
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF5F8F6),
            foregroundColor: Color(0xFF173B33),
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE3EBE6))),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAF9),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDCE7E1))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF146C55), width: 1.7)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        home: MandaiSplashGate(
            builder: (onLandingReady) =>
                Shell(onInitialLandingReady: onLandingReady)),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key, this.onInitialLandingReady});
  final VoidCallback? onInitialLandingReady;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool _initialLandingSignalled = false;
  final api = Api();
  late final PaymentReturnLinks _paymentReturnLinks = PaymentReturnLinks(_onStripeReturn);
  String? _pendingStripeReturnSession;
  final email = TextEditingController(text: 'admin@demo.local');
  final loginEmailFocus = FocusNode();
  final password = TextEditingController();
  String? _authenticatedEmail;
  bool _showLoginPage = false;
  bool busy = false;
  String error = '';
  List<dynamic> products = [];
  final search = TextEditingController();
  String selectedCategory = 'All';
  int customerTab = 0;
  Map<String, dynamic>? _accountProfile;
  bool _accountLoading = false;
  String? _accountError;
  List<dynamic> myOrders = [];
  bool ordersBusy = false;
  final Map<int, int> cart = {};
  final ValueNotifier<int> cartBadgeCount = ValueNotifier<int>(0);

  void _updateCartBadge() {
    cartBadgeCount.value =
        cart.values.fold<int>(0, (sum, quantity) => sum + quantity);
  }

  final addressController =
      TextEditingController(text: 'Demo delivery address, Singapore 000000');
  bool checkoutBusy = false;
  String? pendingCheckoutKey;
  int bannerIndex = 0;
  VideoPlayerController? promoVideo;
  @override
  void initState() {
    super.initState();
    _paymentReturnLinks.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
    // video_player asset playback is not supported by the official plugin on Windows/Linux.
    final supported = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (supported) {
      final controller = VideoPlayerController.asset('assets/promo.mp4');
      promoVideo = controller;
      controller.initialize().then((_) async {
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.play();
        if (mounted) setState(() {});
      }).catchError((Object _) {
        if (mounted) setState(() => promoVideo = null);
      });
    }
  }

  @override
  void dispose() {
    _paymentReturnLinks.dispose();
    promoVideo?.dispose();
    cartBadgeCount.dispose();
    loginEmailFocus.dispose();
    email.dispose();
    password.dispose();
    search.dispose();
    addressController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final route =
          api.role == 'admin' ? '/api/admin/products' : '/api/products';
      products = await api.request('GET', route) as List<dynamic>;
      error = '';
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() => busy = false);
    // Signal the splash only for the initial catalogue load, never for refreshes.
    if (!_initialLandingSignalled) {
      _initialLandingSignalled = true;
      await _prepareFirstLandingFrame();
      if (mounted) {
        // Allow the loaded catalogue subtree to complete layout/paint before fade.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onInitialLandingReady?.call();
        });
      }
    }
  }

  Future<void> _prepareFirstLandingFrame() async {
    // Images rendered by the hero carousel are decoded before the overlay fades.
    // Failure of any asset must not trap the user on the splash screen.
    final initialImages = <ImageProvider>[
      const AssetImage('assets/banner/wildlife_01.jpg'),
      const AssetImage('assets/banner/wildlife_02.jpg'),
      const AssetImage('assets/banner/wildlife_03.jpg'),
    ];
    if (products.isNotEmpty) {
      final p = products.first as Map<String, dynamic>;
      final primary = (p['image_url'] ?? '').toString().trim();
      final frames = _spinUrls(p);
      final source = primary.isNotEmpty
          ? primary
          : (frames.isNotEmpty ? frames.first : '');
      if (source.isNotEmpty) {
        initialImages.add(NetworkImage(_mediaUrl(source)));
      } else {
        initialImages.add(AssetImage(_imageAsset(p)));
      }
    }
    try {
      await Future.wait(initialImages.map((provider) =>
              precacheImage(provider, context).catchError((Object _) {})))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // A missing image/network timeout shows the existing image fallback.
    }
  }

  Future<void> signIn() async {
    final attemptedEmail = email.text.trim();
    setState(() => busy = true);
    try {
      await api.login(attemptedEmail, password.text);
      if (!mounted) return;
      setState(() {
        _authenticatedEmail = attemptedEmail;
        _accountProfile = null;
        _accountError = null;
        _showLoginPage = false;
        error = '';
      });
      await load();
      if (_pendingStripeReturnSession != null) {
        final sessionId = _pendingStripeReturnSession!;
        _pendingStripeReturnSession = null;
        await _onStripeReturn(sessionId);
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> message(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Done')));
      }
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> buy(Map<String, dynamic> product) async {
    if (api.token == null || api.role == 'admin') return;
    int quantity = 1;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text('Buy ${product['name']}'),
                  content: Row(children: [
                    IconButton(
                        onPressed: quantity > 1
                            ? () => update(() => quantity--)
                            : null,
                        icon: const Icon(Icons.remove)),
                    Text('$quantity'),
                    IconButton(
                        onPressed: () => update(() => quantity++),
                        icon: const Icon(Icons.add))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm'))
                  ],
                )));
    if (ok != true) return;
    // One key per user action; generated from time and counter-like monotonic microseconds.
    // Do not regenerate it for a transport retry of the same operation.
    final key =
        'purchase-${DateTime.now().toUtc().microsecondsSinceEpoch}-${product['id']}';
    await message(() async {
      final order = await api.request('POST', '/api/purchases',
          key: key, data: {'product_id': product['id'], 'quantity': quantity});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #${order['order_id']} completed')));
      }
    });
  }

  Future<void> editProduct([Map<String, dynamic>? product]) async {
    if (api.role != 'admin') return;
    final name =
        TextEditingController(text: product?['name']?.toString() ?? '');
    final category = TextEditingController(
        text: product?['category']?.toString() ?? 'Merchandise');
    final description =
        TextEditingController(text: product?['description']?.toString() ?? '');
    final price =
        TextEditingController(text: product?['price']?.toString() ?? '0.00');
    final stock =
        TextEditingController(text: product?['stock']?.toString() ?? '0');
    final image =
        TextEditingController(text: product?['image_url']?.toString() ?? '');
    final spin = TextEditingController(
        text: product?['spin_image_urls']?.toString() ?? '');
    // Keep the editor's active status local until Save is confirmed.
    final active = ValueNotifier<bool>(product?['is_active'] != false);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 920,
            maxHeight: MediaQuery.sizeOf(ctx).height - 24,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        product == null
                            ? 'Add merchandise'
                            : 'Edit merchandise',
                        style: Theme.of(ctx).textTheme.headlineSmall)),
                IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx, false)),
              ]),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                    child: Form(
                        key: formKey,
                        child: Column(children: [
                          TextFormField(
                              controller: name,
                              decoration: const InputDecoration(
                                  labelText: 'Product name'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Required'
                                  : null),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: category,
                              decoration:
                                  const InputDecoration(labelText: 'Category')),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: description,
                              decoration: const InputDecoration(
                                  labelText: 'Description'),
                              maxLines: 2),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: TextFormField(
                                    controller: price,
                                    decoration: const InputDecoration(
                                        labelText: 'Price (SGD)'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    validator: (v) =>
                                        (double.tryParse(v ?? '') ?? -1) < 0
                                            ? 'Invalid price'
                                            : null)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextFormField(
                                    controller: stock,
                                    decoration: const InputDecoration(
                                        labelText: 'Stock'),
                                    keyboardType: TextInputType.number,
                                    validator: (v) =>
                                        (int.tryParse(v ?? '') ?? -1) < 0
                                            ? 'Invalid stock'
                                            : null)),
                          ]),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<bool>(
                            valueListenable: active,
                            builder: (context, isActive, _) => CheckboxListTile(
                              key: const Key('product-active-checkbox'),
                              title: const Text('Active product'),
                              subtitle: Text(isActive
                                  ? 'Visible in customer catalogue'
                                  : 'Hidden from customer catalogue'),
                              value: isActive,
                              onChanged: (value) => active.value = value ?? false,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: image,
                              decoration: const InputDecoration(
                                  labelText: 'Product image URL')),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: spin,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText:
                                      '360° photo URLs (one URL per line)')),
                        ]))),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                const SizedBox(width: 10),
                FilledButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(ctx, true);
                      }
                    },
                    child: const Text('Save')),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (saved == true) {
      final data = {
        'name': name.text.trim(),
        'category': category.text.trim(),
        'description': description.text.trim(),
        'price': price.text.trim(),
        'stock': int.parse(stock.text),
        'is_active': active.value,
        'image_url': image.text.trim(),
        'spin_image_urls': spin.text.trim(),
      };
      await message(() async {
        await api.request(
            product == null ? 'POST' : 'PUT',
            product == null
                ? '/api/admin/products'
                : '/api/admin/products/${product['id']}',
            data: data);
      });
    }
    for (final c in [name, category, description, price, stock, image, spin]) {
      c.dispose();
    }
    active.dispose();
  }

  String _mediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final base = Uri.tryParse(apiBase);
    final source = Uri.tryParse(value.replaceAll(String.fromCharCode(92), '/'));
    if (base == null || !base.hasAuthority || source == null) return value;

    // URLs created on the development machine are never valid on a remote device.
    if (source.hasScheme && (source.scheme == 'http' || source.scheme == 'https')) {
      if (source.host == 'localhost' || source.host == '127.0.0.1' ||
          source.host == '10.0.2.2') {
        return base.resolveUri(Uri(path: source.path,
          query: source.hasQuery ? source.query : null)).toString();
      }
      return source.toString(); // Preserve real public/CDN image URLs.
    }
    // Both '/media/...' and 'media/...' resolve relative to the configured API.
    if (value.startsWith('//')) return '${base.scheme}:$value';
    return base.resolve(value.startsWith('/') ? value : '/$value').toString();
  }

  List<String> _spinUrls(Map<String, dynamic> p) => (p['spin_image_urls'] ?? '')
      .toString()
      .split(RegExp(r'\r?\n|,'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Widget _productImage(Map<String, dynamic> product, {bool openViewer = true}) {
    final primary = (product['image_url'] ?? '').toString().trim();
    final frames = _spinUrls(product);
    final imageUrl =
        primary.isNotEmpty ? primary : (frames.isNotEmpty ? frames.first : '');
    return InkWell(
      onTap: !openViewer || imageUrl.isEmpty
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => CommerceMediaDialog(
                  product: product,
                  apiBase: apiBase,
                  fallbackAsset: 'assets/gift.png',
                ),
              ),
      child: imageUrl.isEmpty
          ? Image.asset(_imageAsset(product), fit: BoxFit.contain)
          : Image.network(_mediaUrl(imageUrl),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Product image failed: ${_mediaUrl(imageUrl)} — $error');
                return Image.asset(_imageAsset(product), fit: BoxFit.contain);
              }),
    );
  }

  Widget _statusChip(String label, {bool positive = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: positive ? const Color(0xFFE9F6EF) : const Color(0xFFFFF3E6),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: positive
                    ? const Color(0xFF13734D)
                    : const Color(0xFFA26823))),
      );

  Widget _metric(String label, String value, IconData icon) => Expanded(
        child: Card(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFEAF4EE),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: const Color(0xFF146C55))),
            const SizedBox(width: 14),
            Flexible(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF183D32))),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B8278))),
                ])),
          ]),
        )),
      );

  Widget _loginView() => LayoutBuilder(builder: (context, size) {
        final wide = size.maxWidth >= 800;
        final loginForm = Card(
            child: Padding(
                padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 400 ? 16 : 28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.forest_rounded,
                          size: 42, color: evergreen),
                      const SizedBox(height: 12),
                      Text(
                          'Log In',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: forest)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: email,
                          focusNode: loginEmailFocus,
                          decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.email_outlined))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: password,
                          obscureText: true,
                          onSubmitted: (_) {
                            if (!busy) signIn();
                          },
                          decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline))),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: busy ? null : signIn,
                          child: Text(busy ? 'Signing in…' : 'Log In')),
                      if (error.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error,
                                style: const TextStyle(color: Colors.red))),
                      const SizedBox(height: 12),
                      TextButton.icon(
                          onPressed: () => setState(() {
                                _showLoginPage = false;
                                error = '';
                              }),
                          icon: const Icon(Icons.storefront_outlined),
                          label:
                              const Text('Browse merchandise without login')),
                      const SizedBox(height: 18),
                      const Text('Independent technical assessment demo',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 11)),
                    ])));
        return Center(
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: wide
                          ? Row(children: [
                              const Expanded(child: StoreLoginIntroduction()),
                              SizedBox(width: 420, child: loginForm),
                            ])
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: loginForm),
                    ))));
      });

  Future<void> _confirmDeleteProduct(Map<String, dynamic> product) async {
    if (api.role != 'admin') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${product['name']}" from the active catalogue? '
            'This permanently deletes the product ONLY if it has no transactions. Products with transaction history cannot be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await message(() async {
      final result = await api.request('DELETE', '/api/admin/products/${product['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['deleted'] == true
              ? 'Product permanently deleted.'
              : 'Deletion was not completed.'),
        ));
      }
    });
  }

  Future<void> _openTestingSummary() async {
    if (api.role != 'admin') return;
    Map<String, dynamic>? report;
    String? failure;
    try {
      final response = await api.request('GET', '/api/admin/testing/report');
      if (response is Map<String, dynamic>) report = response;
    } catch (error) {
      failure = error.toString();
    }
    if (!mounted) return;
    final suites = (report?['suites'] as List?)
            ?.whereType<Map<String, dynamic>>().toList() ?? <Map<String, dynamic>>[];
    final criteria = (report?['acceptance_criteria'] as List?)
            ?.whereType<Map<String, dynamic>>().toList() ?? <Map<String, dynamic>>[];
    final stages = (report?['stress_stages'] as List?)
            ?.whereType<Map<String, dynamic>>().toList() ?? <Map<String, dynamic>>[];
    final sql = report?['previously_verified_sqlserver_concurrency'];
    final sqlEvidence = sql is Map<String, dynamic> ? sql : null;
    final summary = report?['summary'];
    final counts = summary is Map<String, dynamic> ? summary : <String, dynamic>{};

    Color statusColor(String value) => value == 'PASS' ? Colors.green.shade700
        : value == 'FAIL' ? Colors.red.shade700 : Colors.orange.shade800;
    Widget statusChip(String status) => Text(status,
        style: TextStyle(color: statusColor(status), fontWeight: FontWeight.bold,
            fontSize: 12));
    String readable(String name) => name.replaceFirst(RegExp(r'^test_'), '')
        .replaceAll('_', ' ');
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('Question 5 — Testing Report',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close), tooltip: 'Close'),
              ]),
              Expanded(child: ListView(children: [
                Text('Last generated: ${report?['generated_at'] ?? 'No report'}',
                    style: const TextStyle(fontSize: 12)),
                if (failure != null) Text('Report error: $failure',
                    style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  Chip(label: Text('PASS ${counts['passed'] ?? 0}')),
                  Chip(label: Text('FAIL ${counts['failed'] ?? 0}')),
                  Chip(label: Text('NOT RUN ${counts['not_run'] ?? 0}')),
                ]),
                section('Acceptance criteria — Question 5'),
                if (criteria.isEmpty) const Text(
                    'AC mapping not available. Update scripts/run_tests.py and run the tests again.'),
                ...criteria.map((ac) => Card(child: Padding(
                  padding: const EdgeInsets.all(12), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${ac['id']} — ${ac['requirement']}',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      statusChip('${ac['status'] ?? 'NOT VERIFIED'}'),
                    ]),
                    const SizedBox(height: 5),
                    Text('${ac['note'] ?? ''}', style: const TextStyle(fontSize: 12)),
                    if (ac['sqlserver_concurrency_evidence'] != null)
                      Text('SQL Server evidence: ${ac['sqlserver_concurrency_evidence']}',
                          style: const TextStyle(fontSize: 12)),
                  ])))),
                section('Automated test suites'),
                ...suites.map((suite) {
                  final cases = (suite['test_cases'] as List?)
                      ?.whereType<Map<String, dynamic>>().toList() ?? <Map<String, dynamic>>[];
                  final name = '${suite['name'] ?? 'Unnamed suite'}';
                  final status = '${suite['status'] ?? 'NOT RUN'}';
                  return Card(child: ExpansionTile(
                    title: Row(children: [
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8), statusChip(status),
                    ]),
                    subtitle: Text(
                      cases.isNotEmpty
                          ? '${suite['passed']} passed · ${suite['failed']} failed · ${suite['skipped']} skipped'
                          : '${suite['details'] ?? ''}',
                      style: const TextStyle(fontSize: 12)),
                    children: [
                      if (cases.isEmpty)
                        const Padding(padding: EdgeInsets.all(12), child: Text(
                          'No individual test-case results recorded for this suite.')),
                      ...cases.map((test) => ListTile(
                        dense: true,
                        title: Text(readable('${test['name'] ?? ''}')),
                        subtitle: test['message'] == null || '${test['message']}'.isEmpty
                            ? null : Text('${test['message']}'),
                        trailing: statusChip('${test['status'] ?? 'UNKNOWN'}'),
                      )),
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(alignment: Alignment.centerLeft, child: Text(
                          '${suite['details'] ?? ''}', style: const TextStyle(fontSize: 11)))),
                    ],
                  ));
                }),
                section('Load test — GET /api/products (read-only)'),
                if (stages.isEmpty) const Text('Stage details not available for this run.'),
                ...stages.map((stage) {
                  final timing = stage['latency_ms'];
                  final latency = timing is Map ? timing : const {};
                  return ListTile(
                    dense: true,
                    title: Text('${stage['concurrency']} concurrent workers — '
                        '${stage['success']}/${stage['requests']} successful'),
                    subtitle: Text('Errors: ${stage['errors']} · '
                        'P95: ${latency['p95'] ?? 'N/A'} ms · '
                        'Throughput: ${stage['throughput_rps']} req/s'),
                    trailing: statusChip(stage['pass'] == true ? 'PASS' : 'FAIL'),
                  );
                }),
                section('SQL Server concurrency — separate previous verification'),
                if (sqlEvidence == null)
                  const Text('No previous SQL Server concurrency result available.'),
                if (sqlEvidence != null) ...[
                  Text('Status: ${sqlEvidence['status']} · '
                      '${sqlEvidence['passed'] ?? '?'} passed, '
                      '${sqlEvidence['failed'] ?? '?'} failed'),
                  const Text('Not re-executed by Run All Test.',
                      style: TextStyle(fontSize: 12)),
                  ...((sqlEvidence['test_cases'] as List?)
                      ?.whereType<Map<String, dynamic>>() ?? <Map<String, dynamic>>[])
                      .map((c) => ListTile(dense: true,
                        title: Text('${c['test_case'] ?? c['name'] ?? 'Test case'}'),
                        subtitle: Text('${c['expected_result'] ?? ''}'),
                        trailing: statusChip('${c['testing_status'] ?? c['status'] ?? 'UNKNOWN'}'))),
                ],
                const SizedBox(height: 12),
                const Text('Scope: Mandai Question 5 only. Mocked API contracts do not prove '
                    'a full browser journey. SQL Server write tests are executed separately.',
                    style: TextStyle(fontSize: 12)),
              ])),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () {
                  Navigator.pop(ctx);
                  _runAllTestsFromFrontend();
                }, child: const Text('Run All Test')),
                TextButton(onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _runAllTestsFromFrontend() async {
    if (api.role != 'admin') return;
    try {
      await api.request('POST', '/api/admin/testing/run-all');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start Run All Test: $error')),
      );
      return;
    }
    if (!mounted) return;
    // Poll a bounded number of times. The server job continues if this dialog closes.
    final progress = ValueNotifier<String>('Running Question 5 tests...');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Run All Test'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.startsWith('Running')) const CircularProgressIndicator(),
              const SizedBox(height: 16), Text(value),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Close (tests continue)'))],
      ),
    ));
    try {
      for (var i = 0; i < 600; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final result = await api.request('GET', '/api/admin/testing/run-all/status');
        if (result is! Map) continue;
        final state = result['state']?.toString() ?? 'unknown';
        if (state == 'completed' || state == 'failed') {
          progress.value = 'Test run $state';
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Run All Test: $state. Open Testing summary for details.')),
          );
          return;
        }
      }
      progress.value = 'Test is still running; check the Testing summary.';
    } catch (error) {
      progress.value = 'Unable to read progress: $error';
    }
  }

  Widget _productCard(Map<String, dynamic> p) {
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final isActive = p['is_active'] != false;
    final available = stock > 0 && isActive;
    final isAdmin = api.role == 'admin';
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            height: 98,
            width: double.infinity,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFEAF4EC), Color(0xFFF4F0DF)]),
                borderRadius: BorderRadius.circular(15)),
            child: _productImage(p)),
        const SizedBox(height: 14),
        Text(p['category']?.toString().toUpperCase() ?? 'MERCHANDISE',
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: Color(0xFF768C7E),
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(p['name']?.toString() ?? 'Product',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF203D33))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: Text('S\$${p['price']}',
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF146C55)))),
          _statusChip(
              isActive
                  ? (available ? '$stock in stock' : 'Sold out')
                  : 'Inactive',
              positive: available),
        ]),
        const Spacer(),
        const SizedBox(height: 14),
        if (isAdmin)
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => editProduct(p),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit'))),
            const SizedBox(width: 7),
            IconButton(
                tooltip: 'Delete product',
                onPressed: !isActive ? null : () => _confirmDeleteProduct(p),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
          ])
        else
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: available ? () => buy(p) : null,
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text('Buy now'))),
      ]),
    ));
  }

  Widget _inventoryView() {
    final isAdmin = api.role == 'admin';
    final categories = <String>{'All',
      ...products.map((p) => (p['category'] ?? 'Merchandise').toString())}.toList();
    final chosenCategory = categories.contains(selectedCategory) ? selectedCategory : 'All';
    final query = search.text.trim().toLowerCase();
    final visible = products.cast<Map<String, dynamic>>().where((p) {
      final category = (p['category'] ?? '').toString();
      final name = (p['name'] ?? '').toString().toLowerCase();
      final description = (p['description'] ?? '').toString().toLowerCase();
      return (chosenCategory == 'All' || category == chosenCategory) &&
          (query.isEmpty || name.contains(query) ||
           category.toLowerCase().contains(query) || description.contains(query)) &&
          (!inStockOnly || ((p['stock'] as num?)?.toInt() ?? 0) > 0);
    }).toList();
    if (sortBy == 'Name') {
      visible.sort((a,b) => '${a['name']}'.compareTo('${b['name']}'));
    } else if (sortBy == 'Price low' || sortBy == 'Price high') {
      double price(Map<String,dynamic> p) => double.tryParse('${p['price']}') ?? 0;
      visible.sort((a,b) => sortBy == 'Price low' ?
          price(a).compareTo(price(b)) : price(b).compareTo(price(a)));
    }
    final filters = StoreFilterPanel(
      categories: categories,
      category: chosenCategory,
      onCategory: (v) => setState(() { selectedCategory = v; _resetCatalogPaging(); }),
      inStockOnly: inStockOnly,
      onInStockOnly: (v) => setState(() { inStockOnly = v; _resetCatalogPaging(); }),
      sort: sortBy,
      onSort: (v) => setState(() { sortBy = v; _resetCatalogPaging(); }),
    );
    final active = products.where((p) => p['is_active'] != false).length;
    final stock = products.fold<int>(
        0, (sum, p) => sum + ((p['stock'] as num?)?.toInt() ?? 0));
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 660;
      final wide = box.maxWidth >= 750;
      final gridWidth = box.maxWidth - (wide ? 231 : 0);
      final cols = gridWidth >= 1200
          ? 4
          : gridWidth >= 900
              ? 3
              : gridWidth >= 600
                  ? 2
                  : 1;
      return RefreshIndicator(
          onRefresh: load,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF174D3C), Color(0xFF29775B)]),
                          borderRadius: BorderRadius.circular(24)),
                      child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('WILDLIFE MERCHANDISE',
                                      style: TextStyle(
                                          color: Color(0xFFCAE5D2),
                                          fontSize: 11,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(
                                      isAdmin
                                          ? 'Inventory dashboard'
                                          : 'Discover something wild',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 5),
                                  Text(
                                      isAdmin
                                          ? 'Manage your catalogue and stock.'
                                          : 'Wildlife-inspired gifts and keepsakes.',
                                      style: const TextStyle(
                                          color: Color(0xFFDCEAE1))),
                                ]),
                            if (isAdmin)
                              FilledButton.icon(
                                  onPressed: () => editProduct(),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF146C55)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add product')),
                          ])),
                  const SizedBox(height: 22),
                  if (isAdmin) ...[
                    if (narrow) ...[
                      Row(children: [
                        _metric('Products', '${products.length}',
                            Icons.inventory_2_outlined),
                        _metric('Active', '$active', Icons.check_circle_outline)
                      ]),
                      Row(children: [
                        _metric('Stock units', '$stock', Icons.widgets_outlined)
                      ]),
                    ] else
                      Row(children: [
                        _metric('Products', '${products.length}',
                            Icons.inventory_2_outlined),
                        _metric(
                            'Active', '$active', Icons.check_circle_outline),
                        _metric(
                            'Stock units', '$stock', Icons.widgets_outlined),
                      ]),
                    const SizedBox(height: 14),
                  ],
                  if (!wide)
                    Align(alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _showMobileFilters,
                        icon: const Icon(Icons.tune),
                        label: const Text('Filters'))),
                  Row(children: [
                    Expanded(
                        child: Text(
                            isAdmin
                                ? 'Product catalogue'
                                : 'Explore merchandise',
                            style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF203D33)))),
                    IconButton(
                        onPressed: busy ? null : load,
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh_rounded)),
                  ]),
                  if (error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(error,
                            style: const TextStyle(color: Color(0xFFB42318)))),
                  if (busy) const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                ])),
            SliverToBoxAdapter(child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide) ...[
                  SizedBox(width: 215, child: filters),
                  const SizedBox(width: 16),
                ],
                Expanded(child: visible.isEmpty && !busy
                  ? const Padding(padding: EdgeInsets.all(24),
                      child: Center(child: Text('No matching products found.')))
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) => _productCard(visible[i]),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 390))),
              ])),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            // Footer is part of the scroll content, never a fixed bottom overlay.
            SliverToBoxAdapter(
                child: StoreFooter(
              onRunConcurrencyTests: api.role == 'admin' ? _openConcurrencyTests : null,
              onTestingSummary: api.role == 'admin' ? _openTestingSummary : null,
            )),
          ]));
    });
  }

  static const forest = Color(0xFF174D3C);
  static const evergreen = Color(0xFF146C55);
  static const muted = Color(0xFF607B6D);

  void _switchCustomerTab(int tab) {
    // Admin may browse the dashboard/account, but not customer transactions.
    if (api.role == 'admin' && (tab == 1 || tab == 2)) return;
    setState(() => customerTab = tab);
    if (tab == 2) _loadOrders();
    if (tab == 3) _loadAccount();
  }

  Future<void> _loadAccount() async {
    final tokenAtRequest = api.token;
    if (tokenAtRequest == null || _accountLoading) return;
    setState(() {
      _accountLoading = true;
      _accountError = null;
    });
    try {
      final result = await api.request('GET', '/api/account/me');
      if (!mounted || api.token != tokenAtRequest) return;
      setState(() => _accountProfile = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (!mounted || api.token != tokenAtRequest) return;
      setState(() => _accountError = '$e');
    } finally {
      if (mounted && api.token == tokenAtRequest) {
        setState(() => _accountLoading = false);
      }
    }
  }

  Future<void> _loadOrders() async {
    setState(() => ordersBusy = true);
    try {
      final result = await api.request('GET', '/api/orders/my/details');
      if (mounted) setState(() => myOrders = result as List<dynamic>);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load orders: $e')));
      }
    } finally {
      if (mounted) setState(() => ordersBusy = false);
    }
  }

  String _imageAsset(Map<String, dynamic> p) {
    final name = (p['name'] ?? '').toString().toLowerCase();
    if (name.contains('panda')) return 'assets/panda.png';
    if (name.contains('elephant')) return 'assets/elephant.png';
    if (name.contains('shirt')) return 'assets/shirt.png';
    if (name.contains('bottle')) return 'assets/bottle.png';
    if (name.contains('tote')) return 'assets/tote.png';
    return 'assets/gift.png';
  }

  bool _addCart(Map<String, dynamic> p, {int quantity = 1}) {
    if (api.token == null) {
      setState(() => _showLoginPage = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please log in before adding products to the cart.')));
      return false;
    }
    final id = (p['id'] as num).toInt();
    final stock = (p['stock'] as num).toInt();
    final existing = cart[id] ?? 0;
    if (existing + quantity > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not enough stock available')));
      return false;
    }
    cart[id] = existing + quantity;
    pendingCheckoutKey = null;
    _updateCartBadge();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${p['name']} added to cart')));
    return true;
  }

  void _showSignUpInfo() {
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Sign up'),
              content: const Text(
                  'Account registration is not available in this assessment demo. Please use an existing demo account.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'))
              ],
            ));
  }

  void _openProductDetails(Map<String, dynamic> p) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (detailContext) => MainMasterLayout(
              signedIn: api.token != null,
              isAdmin: api.role == 'admin',
              userLabel: email.text.trim(),
              cartCount: cartBadgeCount.value,
              cartCountListenable: cartBadgeCount,
              onCart: () {
                Navigator.of(detailContext).pop();
                setState(() => customerTab = 1);
              },
              onSignOut: () {
                Navigator.of(detailContext).pop();
                _signOut();
              },
              onLogin: () {
                Navigator.of(detailContext).pop();
                setState(() {
                  _showLoginPage = true;
                });
              },
              onSignUp: _showSignUpInfo,
              searchController: search,
              onSearchChanged: (_) {},
              onSearchClear: () {
                search.clear();
              },
              onSearchSubmitted: (_) {
                Navigator.of(detailContext).pop();
                setState(() {
                  selectedCategory = 'All';
                  inStockOnly = false;
                  customerTab = 0;
                });
              },
              onBack: () => Navigator.of(detailContext).pop(),
              content: StoreProductDetail(
                product: p,
                image: _productImage(p),
                onAddToCart: (quantity) => _addCart(p, quantity: quantity),
                onBuyNow: (quantity) {
                  if (_addCart(p, quantity: quantity) && mounted) {
                    Navigator.of(detailContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showCheckout();
                    });
                  }
                },
              ),
            )));
  }

  Widget _customerProductCard(Map<String, dynamic> p) => StoreProductCard(
        product: p,
        image: _productImage(p, openViewer: false),
        onOpen: () => _openProductDetails(p),
      );

  Map<String, dynamic>? _cartProduct(int id) {
    for (final p in products) {
      if ((p['id'] as num).toInt() == id) return p as Map<String, dynamic>;
    }
    return null;
  }

  double get _subtotal => cart.entries.fold(0.0, (v, e) {
        final p = _cartProduct(e.key);
        return v +
            (p == null ? 0 : (double.tryParse('${p['price']}') ?? 0) * e.value);
      });
  static const double deliveryFee = 4.90;

  Widget _cartView() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Shopping cart',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 12),
        if (cart.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                      child: Text(
                          'Your cart is empty. Explore our wildlife gifts.')))),
        ...cart.entries.toList().map((entry) {
          final p = _cartProduct(entry.key);
          if (p == null) return const SizedBox.shrink();
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                            width: 78,
                            height: 78,
                            child: _productImage(p, openViewer: false))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${p['name']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text('S\$${p['price']}',
                              style: const TextStyle(color: evergreen)),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                onPressed: entry.value > 1
                                    ? () => setState(() {
                                          cart[entry.key] = entry.value - 1;
                                          pendingCheckoutKey = null;
                                          _updateCartBadge();
                                        })
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline)),
                            Text('${entry.value}'),
                            IconButton(
                                onPressed: entry.value <
                                        ((p['stock'] as num?)?.toInt() ?? 0)
                                    ? () => setState(() {
                                          cart[entry.key] = entry.value + 1;
                                          pendingCheckoutKey = null;
                                          _updateCartBadge();
                                        })
                                    : null,
                                icon: const Icon(Icons.add_circle_outline)),
                            IconButton(
                                tooltip: 'Remove',
                                onPressed: () => setState(() {
                                      cart.remove(entry.key);
                                      pendingCheckoutKey = null;
                                      _updateCartBadge();
                                    }),
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent)),
                          ])
                        ]))
                  ])));
        }),
        if (cart.isNotEmpty) ...[
          const SizedBox(height: 16),
          _amountLine('Subtotal', _subtotal),
          _amountLine('Delivery fee', deliveryFee),
          const Divider(),
          _amountLine('Total', _subtotal + deliveryFee, bold: true),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () => _showCheckout(),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Proceed to checkout')),
        ]
      ]);

  Widget _amountLine(String text, double amount, {bool bold = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(text,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text('S\$${amount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500))
          ]));

  Future<void> _showCheckout() async {
    if (cart.isEmpty) return;
    String method = 'card_demo';
    bool decline = false;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
            builder: (dialogCtx, update) => AlertDialog(
                  title: const Text('Secure checkout'),
                  content: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextField(
                                controller: addressController,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    labelText: 'Delivery address')),
                            const SizedBox(height: 12),
                            const Text(
                                'Delivery address is used for this demo order only.',
                                style: TextStyle(fontSize: 12, color: muted)),
                            const SizedBox(height: 12),
                            const InputDecorator(
                              decoration: InputDecoration(
                                  labelText: 'Redeem points (coming soon)',
                                  prefixIcon: Icon(Icons.stars_outlined)),
                              child: Text('Not available in this demo',
                                  style: TextStyle(color: muted)),
                            ),
                            const SizedBox(height: 12),
                            const Text('Payment method'),
                            RadioGroup<String>(
                              groupValue: method,
                              onChanged: (value) {
                                if (value != null) update(() => method = value);
                              },
                              child: const Column(children: [
                                RadioListTile<String>(
                                    title: Text('Demo Credit Card •••• 4242'),
                                    value: 'card_demo'),
                                RadioListTile<String>(
                                    title: Text('Demo PayNow'),
                                    value: 'paynow_demo'),
                                RadioListTile<String>(
                                    title: Text('Stripe secure online payment (Sandbox)'),
                                    value: 'stripe_test'),
                              ]),
                            ),
                            if (method != 'stripe_test') CheckboxListTile(
                                value: decline,
                                onChanged: (v) =>
                                    update(() => decline = v ?? false),
                                title: const Text(
                                    'Simulate declined payment (test)')),
                            _amountLine('Subtotal', _subtotal),
                            _amountLine('Delivery', deliveryFee),
                            _amountLine('Total', _subtotal + deliveryFee,
                                bold: true),
                            Text(
                                method == 'stripe_test'
                                  ? 'Sandbox: card details are entered on Stripe. Payment is confirmed only after a verified webhook.'
                                  : 'Payment is simulated. No card numbers are collected; Luhn verification uses synthetic test data only.',
                                style: const TextStyle(fontSize: 12, color: muted))
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Back')),
                    FilledButton(
                        onPressed: checkoutBusy
                            ? null
                            : () => Navigator.pop(dialogCtx, true),
                        child: Text(method == 'stripe_test' ? 'Continue to Stripe' : 'Confirm & pay'))
                  ],
                )));
    if (confirmed != true || !mounted) return;
    if (addressController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a delivery address (minimum 10 characters)')));
      return;
    }
    if (method == 'stripe_test') {
      await _checkoutWithStripe();
      return;
    }
    setState(() => checkoutBusy = true);
    pendingCheckoutKey ??= 'checkout-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final items = cart.entries
          .map((e) => {'product_id': e.key, 'quantity': e.value})
          .toList();
      final response = await api
          .request('POST', '/api/checkout', key: pendingCheckoutKey!, data: {
        'items': items,
        'delivery_address': addressController.text.trim(),
        'payment_method': method,
        'simulate_decline': decline
      });
      if (!mounted) {
        return;
      }
      setState(() {
        cart.clear();
        pendingCheckoutKey = null;
        customerTab = 2;
        _updateCartBadge();
      });
      await load();
      await _loadOrders();
      if (mounted) {
        await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Order confirmed'),
                    content: Text(
                        'Order #${response['order_id']}\nPayment: ${response['payment_status']}\nTotal: S\$${response['total_amount']}\n\nThis is a simulated payment.'),
                    actions: [
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('View orders'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => checkoutBusy = false);
    }
  }

  // Browser return is a navigation hint. Always ask our authenticated backend
  // to resolve the Stripe Session to the owning order and verify it with Stripe.
  Future<void> _onStripeReturn(String sessionId) async {
    if (!mounted) return;
    if (api.token == null || api.role != 'user') {
      _pendingStripeReturnSession = sessionId;
      setState(() => _showLoginPage = true);
      return;
    }
    try {
      final client = StripeCheckoutClient(apiBase: apiBase, token: api.token!);
      final ref = await client.orderForSession(sessionId);
      final orderId = (ref['order_id'] as num).toInt();
      final verified = await client.reconcile(orderId);
      if (!mounted) return;
      await _loadOrders();
      if (!mounted) return;
      setState(() => customerTab = 2);
      final paid = verified['order_status'] == 'completed' &&
          verified['payment_status'] == 'approved_test';
      if (paid) {
        setState(() {
          cart.clear();
          _stripeCheckoutKey = null;
          _updateCartBadge();
        });
        await load();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(paid
              ? 'Payment verified: ${ref['invoice_number']}'
              : 'Payment not yet confirmed: ${ref['invoice_number']}. Check Orders before retrying.'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unable to verify returned payment. Check Orders; do not pay again. $e'),
      ));
    }
  }

  String? _stripeCheckoutKey;

  Future<void> _checkoutWithStripe() async {
    if (api.token == null || api.role != 'user' || checkoutBusy || cart.isEmpty) return;
    setState(() => checkoutBusy = true);
    // Keep key stable on network uncertainty; never accidentally create a second attempt.
    _stripeCheckoutKey ??= StripeCheckoutClient.newIdempotencyKey();
    final client = StripeCheckoutClient(apiBase: apiBase, token: api.token!);
    try {
      final result = await client.createSession(
        items: cart.entries.map((e) => {'product_id': e.key, 'quantity': e.value}).toList(),
        deliveryAddress: addressController.text.trim(),
        idempotencyKey: _stripeCheckoutKey!,
      );
      if (!mounted) return;
      final orderId = (result['order_id'] as num).toInt();
      final checkoutUrl = (result['checkout_url'] ?? '').toString();
      if (checkoutUrl.isNotEmpty) await client.openStripe(checkoutUrl);
      if (!mounted) return;
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Stripe payment status'),
          content: Text('Invoice ${result['invoice_number']}\n\nComplete payment in Stripe Checkout, then select Check payment status.\n\nDo not pay twice. Returning from the browser does not confirm payment.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Check later')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Check payment status')),
          ],
        ));
      if (!mounted) return;
      final status = await client.reconcile(orderId);
      if (!mounted) return;
      if (status['payment_status'] == 'approved_test' && status['order_status'] == 'completed') {
        setState(() {
          cart.clear();
          _stripeCheckoutKey = null;
          customerTab = 2;
          _updateCartBadge();
        });
        await load();
        await _loadOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stripe sandbox payment verified: ${status['invoice_number']}')));
        }
      } else {
        // Keep cart unchanged; order remains pending or requires reconciliation.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payment status: ${status['payment_status']}. Invoice: ${status['invoice_number']}. Check Orders before retrying.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Stripe payment: $error. Do not start another payment until status is checked.')));
      }
    } finally {
      if (mounted) setState(() => checkoutBusy = false);
    }
  }

  static const int _catalogPageSize = 12;
  int _catalogShown = _catalogPageSize;
  void _resetCatalogPaging() => _catalogShown = _catalogPageSize;

  bool inStockOnly = false;
  String sortBy = 'Default';

  void _showMobileFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refreshSheet) {
          // Rebuild the bottom sheet from the CURRENT filter state.
          // The customer catalogue remains controlled by the parent Shell.
          final categories = <String>{
            'All',
            ...products.map((p) => (p['category'] ?? 'Merchandise').toString()),
          }.toList();
          final chosenCategory =
              categories.contains(selectedCategory) ? selectedCategory : 'All';
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.8,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Filter products',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700))),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ]),
                    StoreFilterPanel(
                      categories: categories,
                      category: chosenCategory,
                      onCategory: (value) {
                        setState(() {
                          selectedCategory = value;
                          _resetCatalogPaging();
                        });
                        refreshSheet(() {});
                      },
                      inStockOnly: inStockOnly,
                      onInStockOnly: (value) {
                        setState(() {
                          inStockOnly = value;
                          _resetCatalogPaging();
                        });
                        refreshSheet(() {});
                      },
                      sort: sortBy,
                      onSort: (value) {
                        setState(() {
                          sortBy = value;
                          _resetCatalogPaging();
                        });
                        refreshSheet(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _storefrontView() {
    final categories = <String>{
      'All',
      ...products.map((p) => (p['category'] ?? 'Merchandise').toString())
    }.toList();
    final chosenCategory =
        categories.contains(selectedCategory) ? selectedCategory : 'All';
    final query = search.text.trim().toLowerCase();
    final visible = products
        .where((raw) {
          final p = raw as Map<String, dynamic>;
          final name = (p['name'] ?? '').toString().toLowerCase();
          final category = (p['category'] ?? '').toString();
          return (chosenCategory == 'All' || category == chosenCategory) &&
              (query.isEmpty ||
                  name.contains(query) ||
                  category.toLowerCase().contains(query)) &&
              (!inStockOnly || ((p['stock'] as num?)?.toInt() ?? 0) > 0);
        })
        .cast<Map<String, dynamic>>()
        .toList();
    if (sortBy == 'Name') {
      visible.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    } else if (sortBy == 'Price low' || sortBy == 'Price high') {
      double price(Map<String, dynamic> p) =>
          double.tryParse('${p['price']}') ?? 0;
      visible.sort((a, b) => sortBy == 'Price low'
          ? price(a).compareTo(price(b))
          : price(b).compareTo(price(a)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 750;
      final sidebarWidth = wide ? 215.0 : 0.0;
      final contentWidth =
          constraints.maxWidth - sidebarWidth - (wide ? 16 : 0);
      // On mobile keep precisely two columns; desktop adapts to available width.
      final columns = wide ? (contentWidth / 240).floor().clamp(2, 5) : 2;
      final filters = StoreFilterPanel(
          categories: categories,
          category: chosenCategory,
          onCategory: (v) => setState(() {
                selectedCategory = v;
                _resetCatalogPaging();
              }),
          inStockOnly: inStockOnly,
          onInStockOnly: (v) => setState(() {
                inStockOnly = v;
                _resetCatalogPaging();
              }),
          sort: sortBy,
          onSort: (v) => setState(() {
                sortBy = v;
                _resetCatalogPaging();
              }));
      final catalog =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('${visible.length} products',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: forest)),
              if (!wide)
                OutlinedButton.icon(
                    onPressed: () => _showMobileFilters(),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Filters')),
              IconButton(
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh products'),
            ]),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Text(error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 10),
        if (visible.isEmpty && !busy)
          const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('No matching merchandise found.')))
        else
          GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: wide ? 365 : 285),
              itemCount: visible.length < _catalogShown
                  ? visible.length
                  : _catalogShown,
              itemBuilder: (context, index) =>
                  _customerProductCard(visible[index])),
        if (visible.length > _catalogShown)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: Text('Scroll to see more products',
                      style: TextStyle(color: muted)))),
      ]);
      return RefreshIndicator(
          onRefresh: load,
          child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification &&
                    notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 520 &&
                    _catalogShown < visible.length) {
                  setState(() => _catalogShown =
                      (_catalogShown + _catalogPageSize)
                          .clamp(0, visible.length));
                }
                return false;
              },
              child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                    color: const Color(0xFF9CBDAE), width: 0.8),
                                borderRadius: BorderRadius.circular(18)),
                            child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('WILDLIFE MERCHANDISE',
                                      style: TextStyle(
                                          color: forest, letterSpacing: 2)),
                                  SizedBox(height: 5),
                                  Text('Discover something wild',
                                      style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.bold,
                                          color: forest)),
                                  Text('Wildlife-inspired gifts and keepsakes',
                                      style: TextStyle(color: muted)),
                                  SizedBox(height: 16),
                                  StoreWildlifeCarousel(),
                                ])),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: sidebarWidth, child: filters),
                                const SizedBox(width: 16),
                                Expanded(child: catalog),
                              ])
                        else
                          catalog,
                        const SizedBox(height: 28),
                        StoreFooter(
                            onRunConcurrencyTests: api.role == 'admin' ? _openConcurrencyTests : null,
                            onTestingSummary: api.role == 'admin' ? _openTestingSummary : null),
                      ]))));
    });
  }

  Future<void> _verifyOrResumeStripe(int orderId) async {
    if (api.token == null || api.role != 'user') return;
    final client = StripeCheckoutClient(apiBase: apiBase, token: api.token!);
    try {
      final verified = await client.reconcile(orderId);
      if (!mounted) return;
      await _loadOrders();
      if (!mounted) return;
      if (verified['order_status'] == 'completed' &&
          verified['payment_status'] == 'approved_test') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Payment confirmed: ${verified['invoice_number']}')));
        return;
      }
      if (verified['stripe_payment_status'] == 'paid') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment verification pending; do not pay again.')));
        return;
      }
      final resume = await client.resume(orderId);
      if (!mounted) return;
      final resumeNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resume Stripe payment'),
          content: Text('Invoice ${resume['invoice_number']} is not paid yet. '
              'Open its existing Stripe Checkout session? No new order will be created.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Resume payment')),
          ],
        ),
      );
      if (resumeNow == true) await client.openStripe('${resume['checkout_url']}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Stripe verification: $e. Do not pay again until status is checked.'),
        ));
      }
    }
  }

  Widget _customerOrdersView() => RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('My purchases',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 8),
        const Text('Order history from the secure backend.',
            style: TextStyle(color: muted)),
        if (ordersBusy) const LinearProgressIndicator(),
        if (!ordersBusy && myOrders.isEmpty)
          const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No purchases yet.'))),
        ...myOrders.map((order) => Card(
            child: ListTile(
                leading:
                    const Icon(Icons.receipt_long_rounded, color: evergreen),
                title: Text('Order #${order['id']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${order['status']} • ${order['payment_status']}'),
                    if (order['status'] == 'pending_payment')
                      TextButton(
                        onPressed: () => _verifyOrResumeStripe((order['id'] as num).toInt()),
                        child: const Text('Verify / Resume Stripe'),
                      ),
                  ],
                ),
                trailing: Text('S\$${order['total_amount']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: forest))))),
      ]));

  void _openConcurrencyTests() {
    if (api.token == null || api.role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sign in as administrator to run development tests.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConcurrentTransactionTestPage(
        runTests: () async {
          final result =
              await api.request('POST', '/api/admin/concurrency-tests');
          return Map<String, dynamic>.from(result as Map);
        },
      ),
    ));
  }

  Widget _accountView() {
    if (_accountLoading && _accountProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_accountError != null && _accountProfile == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Unable to load account: $_accountError'),
        TextButton(onPressed: _loadAccount, child: const Text('Retry')),
      ]));
    }
    final profile = _accountProfile;
    final payment = profile?['payment_method']?.toString();
    // Do not invent saved credit-card details; Stripe stores card data separately.
    final methodLabel = payment == null || payment.trim().isEmpty
        ? null
        : (payment.toLowerCase().contains('stripe') ||
           payment.toLowerCase().contains('card'))
            ? 'Credit Card (Stripe)'
            : payment;
    return CustomerAccountPanel(
      email: profile?['email']?.toString() ?? _authenticatedEmail ?? '',
      deliveryAddress: profile?['delivery_address']?.toString(),
      phoneNumber: profile?['phone_number']?.toString(),
      paymentMethod: methodLabel,
      onSignOut: _signOut,
    );
  }

  void _signOut() {
    setState(() {
      api.token = null;
      api.role = null;
      _authenticatedEmail = null;
      _accountProfile = null;
      _accountError = null;
      _accountLoading = false;
      myOrders = [];
      _showLoginPage = false;
      customerTab = 0;
      selectedCategory = 'All';
      search.clear();
      error = '';
      cart.clear();
      pendingCheckoutKey = null;
      _updateCartBadge();
    });
    load();
  }

  @override
  Widget build(BuildContext context) => MainMasterLayout(
        signedIn: api.token != null,
        isAdmin: api.role == 'admin',
        userLabel: email.text.trim(),
        cartCount: cartBadgeCount.value,
        cartCountListenable: cartBadgeCount,
        onCart: () => setState(() => customerTab = 1),
        onSignOut: _signOut,
        onLogin: () => setState(() {
          _showLoginPage = true;
          error = '';
        }),
        onSignUp: _showSignUpInfo,
        searchController: search,
        onSearchChanged: (_) => setState(() => _resetCatalogPaging()),
        onSearchClear: () {
          search.clear();
          setState(() => _resetCatalogPaging());
        },
        onSearchSubmitted: (_) => setState(() {
          _resetCatalogPaging();
          customerTab = 0;
        }),
        content: api.token == null && _showLoginPage
            ? _loginView()
            : api.role == 'admin'
                ? Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1300),
                        child: customerTab == 3
                            ? _accountView()
                            : Padding(
                                padding: const EdgeInsets.all(20),
                                child: _inventoryView())))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1300),
                        child: customerTab == 0
                            ? _storefrontView()
                            : customerTab == 1
                                ? _cartView()
                                : customerTab == 2
                                    ? _customerOrdersView()
                                    : _accountView())),
        // This navigation bar is docked by Scaffold below the scrollable content.
        bottomNavigationBar: api.token != null
            ? NavigationBar(
                selectedIndex: customerTab,
                onDestinationSelected: _switchCustomerTab,
                destinations: [
                    const NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home'),
                    NavigationDestination(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: 'Cart',
                        enabled: api.role != 'admin'),
                    NavigationDestination(
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: 'Orders',
                        enabled: api.role != 'admin'),
                    const NavigationDestination(
                        icon: Icon(Icons.person_outline), label: 'Account'),
                  ])
            : null,
      );
}
