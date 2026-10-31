part of '../main.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, this.onInitialLandingReady});
  final VoidCallback? onInitialLandingReady;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  void _updateState(VoidCallback action) => setState(action);

  final search = TextEditingController();
  String selectedCategory = 'All';
  int customerTab = 0;
  bool inStockOnly = false;
  String sortBy = 'Default';
  String? _stripeCheckoutKey;
  static const double deliveryFee = 4.90;
  static const forest = Color(0xFF174D3C);
  static const evergreen = Color(0xFF146C55);
  static const muted = Color(0xFF607B6D);

  bool _initialLandingSignalled = false;
  final api = Api();
  late final PaymentReturnLinks _paymentReturnLinks =
      PaymentReturnLinks(_onStripeReturn);
  String? _pendingStripeReturnSession;
  final email = TextEditingController(text: 'admin@demo.local');
  final loginEmailFocus = FocusNode();
  final password = TextEditingController();
  String? _authenticatedEmail;
  bool _showLoginPage = false;
  bool busy = false;
  String error = '';
  List<dynamic> products = [];
  // Shared server-side pagination for customer and administrator catalogues.
  int _catalogGeneration = 0;
  int? _catalogTotalCount;
  String? _catalogCountFilterKey;
  bool _catalogHasMore = true;
  bool _catalogLoadingMore = false;
  int _catalogNextOffset = 0;
  String? _catalogPageError;
  List<String> _catalogCategories = [];
  Map<String, dynamic>? _adminInventoryStats;
  Timer? _catalogSearchDebounce;

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
    _catalogSearchDebounce?.cancel();
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
    final generation = ++_catalogGeneration;
    final isAdmin = api.role == 'admin';
    final countPath = _catalogCountQuery();
    final countNeeded =
        (_catalogCountFilterKey != countPath || _catalogTotalCount == null);
    if (countNeeded) {
      _catalogCountFilterKey = countPath;
      _catalogTotalCount = null;
    }
    setState(() {
      busy = true;
      _catalogLoadingMore = false;
      _catalogHasMore = true;
      _catalogNextOffset = 0;
      _catalogPageError = null;
      products = [];
    });
    if (countNeeded) {
      unawaited(_fetchCatalogCount(generation, countPath));
    }
    try {
      final route = _catalogQuery(_adaptiveCatalogBatch(context), 0);
      final response = await api.request('GET', route);
      if (!mounted || generation != _catalogGeneration) return;
      if (response is! List) {
        throw const FormatException('Expected product list');
      }
      setState(() {
        products = response;
        _catalogNextOffset = response.length;
        _catalogHasMore = response.length == _adaptiveCatalogBatch(context);
        error = '';
      });
      if (_catalogCategories.isEmpty) {
        unawaited(_loadCatalogCategories());
      }
      if (isAdmin) unawaited(_loadAdminInventoryStats(generation));
      {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _catalogGeneration ||
              _catalogHasLocalFilters ||
              !_catalogHasMore ||
              _catalogLoadingMore) {
            return;
          }
          // Fill a tall viewport even when the initial batch cannot scroll.
          final height = MediaQuery.sizeOf(context).height;
          if (products.length < _adaptiveCatalogBatch(context) ||
              height > 950) {
            _fetchNextCatalogPage();
          }
        });
      }
    } catch (e) {
      if (mounted && generation == _catalogGeneration) {
        setState(() => error = '$e');
      }
    }
    if (!mounted || generation != _catalogGeneration) return;
    setState(() => busy = false);
    if (!_initialLandingSignalled) {
      _initialLandingSignalled = true;
      await _prepareFirstLandingFrame();
      if (mounted) {
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
        _adminInventoryStats = null;
        _accountError = null;
        _showLoginPage = false;
        error = '';
      });
      // Reuse the already loaded landing catalogue for customer sign-in.
      // Admin must fetch the authenticated inventory, including inactive items.
      if (api.role == 'admin' || products.isEmpty || error.isNotEmpty) {
        _catalogCategories = [];
        await load();
      }
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
                      Text('Log In',
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
        onSearchChanged: (_) {
          setState(() {});
          _catalogSearchDebounce?.cancel();
          _catalogSearchDebounce =
              Timer(const Duration(milliseconds: 300), _reloadFilteredCatalog);
        },
        onSearchClear: () {
          search.clear();
          _catalogSearchDebounce?.cancel();
          _resetCatalogPaging();
        },
        onSearchSubmitted: (_) {
          setState(() => customerTab = 0);
          _resetCatalogPaging();
        },
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
