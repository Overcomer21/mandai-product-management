part of '../main.dart';

// Extracted from Shell without changing application behaviour.
extension _ShellCatalog on _ShellState {
  int _adaptiveCatalogBatch(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final availableWidth = viewport.width.clamp(0.0, 1300.0);
    final wide = availableWidth >= 750;
    final catalogWidth = availableWidth - (wide ? 231.0 : 0.0) - 32.0;
    final columns = wide ? (catalogWidth / 240).floor().clamp(2, 5) : 2;
    final rowExtent = (wide ? 365.0 : 285.0) + 12.0;
    // Reserve the existing top panel and catalogue heading; prefetch two rows.
    final rows =
        ((viewport.height - 240).clamp(1.0, double.infinity) / rowExtent)
                .ceil() +
            2;
    final required = columns * rows;
    for (final batch in const [10, 15, 20, 30]) {
      if (required <= batch) return batch;
    }
    return 30;
  }

  bool get _catalogHasLocalFilters =>
      search.text.trim().isNotEmpty ||
      selectedCategory != 'All' ||
      inStockOnly ||
      sortBy != 'Default';

  String _catalogQuery(int limit, int offset) {
    final parameters = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (selectedCategory != 'All') parameters['category'] = selectedCategory;
    if (search.text.trim().isNotEmpty) {
      parameters['search'] = search.text.trim();
    }
    if (inStockOnly) parameters['in_stock'] = 'true';
    if (sortBy != 'Default') parameters['sort'] = sortBy;
    final endpoint =
        api.role == 'admin' ? '/api/admin/products' : '/api/products';
    return '$endpoint?${Uri(queryParameters: parameters).query}';
  }

  // Sorting does not affect the number of matching products.

  String _catalogCountQuery() {
    final parameters = <String, String>{};
    if (selectedCategory != 'All') parameters['category'] = selectedCategory;
    if (search.text.trim().isNotEmpty) {
      parameters['search'] = search.text.trim();
    }
    if (inStockOnly) parameters['in_stock'] = 'true';
    final endpoint = api.role == 'admin'
        ? '/api/admin/products/count'
        : '/api/products/count';
    return '$endpoint?${Uri(queryParameters: parameters).query}';
  }

  Future<void> _fetchCatalogCount(int generation, String path) async {
    try {
      final response = await api.request('GET', path);
      if (!mounted || generation != _catalogGeneration) {
        return;
      }
      if (response is! Map || response['total'] is! num) {
        throw const FormatException('Expected catalogue total');
      }
      _updateState(
          () => _catalogTotalCount = (response['total'] as num).toInt());
    } catch (e) {
      if (mounted && generation == _catalogGeneration) {
        debugPrint('Catalogue count unavailable: $e');
      }
    }
  }

  Future<void> _fetchNextCatalogPage() async {
    if (_catalogLoadingMore || !_catalogHasMore) return;
    final generation = _catalogGeneration;
    final limit = _adaptiveCatalogBatch(context);
    final offset = _catalogNextOffset;
    _updateState(() {
      _catalogLoadingMore = true;
      _catalogPageError = null;
    });
    try {
      final page = await api.request('GET', _catalogQuery(limit, offset));
      if (!mounted || generation != _catalogGeneration) {
        return;
      }
      if (page is! List) throw const FormatException('Expected product list');
      final existingIds = products.map((p) => (p as Map)['id']).toSet();
      final unique =
          page.where((p) => p is Map && existingIds.add(p['id'])).toList();
      _updateState(() {
        products = [...products, ...unique];
        _catalogNextOffset += page.length;
        _catalogHasMore = page.length == limit;
      });
    } catch (e) {
      if (mounted && generation == _catalogGeneration) {
        _updateState(() => _catalogPageError = '$e');
      }
    } finally {
      if (mounted && generation == _catalogGeneration) {
        _updateState(() => _catalogLoadingMore = false);
      }
    }
  }

  void _reloadFilteredCatalog() {
    load();
  }

  Future<void> _loadCatalogCategories() async {
    try {
      final endpoint = api.role == 'admin'
          ? '/api/admin/products/categories'
          : '/api/products/categories';
      final result = await api.request('GET', endpoint);
      if (mounted && result is List) {
        _updateState(() =>
            _catalogCategories = result.map((x) => x.toString()).toList());
      }
    } catch (_) {
      // Keep category options from loaded products if metadata is unavailable.
    }
  }

  Future<void> _loadAdminInventoryStats(int generation) async {
    try {
      final result = await api.request('GET', '/api/admin/products/stats');
      if (!mounted || generation != _catalogGeneration || api.role != 'admin') {
        return;
      }
      if (result is Map) {
        _updateState(
            () => _adminInventoryStats = Map<String, dynamic>.from(result));
      }
    } catch (e) {
      debugPrint('Admin inventory stats unavailable: $e');
    }
  }

  String _mediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final base = Uri.tryParse(apiBase);
    final source = Uri.tryParse(value.replaceAll(String.fromCharCode(92), '/'));
    if (base == null || !base.hasAuthority || source == null) return value;

    // URLs created on the development machine are never valid on a remote device.
    if (source.hasScheme &&
        (source.scheme == 'http' || source.scheme == 'https')) {
      if (source.host == 'localhost' ||
          source.host == '127.0.0.1' ||
          source.host == '10.0.2.2') {
        return base
            .resolveUri(Uri(
                path: source.path,
                query: source.hasQuery ? source.query : null))
            .toString();
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
          : Image.network(_mediaUrl(imageUrl), fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
              debugPrint(
                  'Product image failed: ${_mediaUrl(imageUrl)} — $error');
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
                icon:
                    const Icon(Icons.delete_outline, color: Colors.redAccent)),
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

  String _imageAsset(Map<String, dynamic> p) {
    final name = (p['name'] ?? '').toString().toLowerCase();
    if (name.contains('panda')) return 'assets/panda.png';
    if (name.contains('elephant')) return 'assets/elephant.png';
    if (name.contains('shirt')) return 'assets/shirt.png';
    if (name.contains('bottle')) return 'assets/bottle.png';
    if (name.contains('tote')) return 'assets/tote.png';
    return 'assets/gift.png';
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
                _updateState(() => customerTab = 1);
              },
              onSignOut: () {
                Navigator.of(detailContext).pop();
                _signOut();
              },
              onLogin: () {
                Navigator.of(detailContext).pop();
                _updateState(() {
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
                _updateState(() {
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

  void _resetCatalogPaging() {
    _reloadFilteredCatalog();
  }

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
            ..._catalogCategories,
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
                        _updateState(() => selectedCategory = value);
                        _resetCatalogPaging();
                        refreshSheet(() {});
                      },
                      inStockOnly: inStockOnly,
                      onInStockOnly: (value) {
                        _updateState(() => inStockOnly = value);
                        _resetCatalogPaging();
                        refreshSheet(() {});
                      },
                      sort: sortBy,
                      onSort: (value) {
                        _updateState(() => sortBy = value);
                        _resetCatalogPaging();
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
      ..._catalogCategories,
      ...products.map((p) => (p['category'] ?? 'Merchandise').toString())
    }.toList();
    final chosenCategory =
        categories.contains(selectedCategory) ? selectedCategory : 'All';
    final visible = products.cast<Map<String, dynamic>>();
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
          onCategory: (v) {
            _updateState(() => selectedCategory = v);
            _resetCatalogPaging();
          },
          inStockOnly: inStockOnly,
          onInStockOnly: (v) {
            _updateState(() => inStockOnly = v);
            _resetCatalogPaging();
          },
          sort: sortBy,
          onSort: (v) {
            _updateState(() => sortBy = v);
            _resetCatalogPaging();
          });
      final catalog =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                  _catalogTotalCount == null
                      ? 'Loading products...'
                      : '$_catalogTotalCount products',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _ShellState.forest)),
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
        if (_catalogPageError != null)
          Text(_catalogPageError!, style: const TextStyle(color: Colors.red)),
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
              itemCount: visible.length,
              itemBuilder: (context, index) =>
                  _customerProductCard(visible[index])),
        if (_catalogHasMore || _catalogLoadingMore)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: Text('Scroll to see more products',
                      style: TextStyle(color: _ShellState.muted)))),
      ]);
      return RefreshIndicator(
          onRefresh: load,
          child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification &&
                    notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 520 &&
                    _catalogHasMore &&
                    !_catalogLoadingMore) {
                  _fetchNextCatalogPage();
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
                                          color: _ShellState.forest,
                                          letterSpacing: 2)),
                                  SizedBox(height: 5),
                                  Text('Discover something wild',
                                      style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.bold,
                                          color: _ShellState.forest)),
                                  Text('Wildlife-inspired gifts and keepsakes',
                                      style:
                                          TextStyle(color: _ShellState.muted)),
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
                            onRunConcurrencyTests: api.role == 'admin'
                                ? _openConcurrencyTests
                                : null,
                            onTestingSummary: api.role == 'admin'
                                ? _openTestingSummary
                                : null),
                      ]))));
    });
  }
}
