part of '../main.dart';

// Extracted from Shell without changing application behaviour.
extension _ShellAdmin on _ShellState {
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
                              onChanged: (value) =>
                                  active.value = value ?? false,
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

  Future<void> _confirmDeleteProduct(Map<String, dynamic> product) async {
    if (api.role != 'admin') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${product['name']}" from the active catalogue? '
            'This permanently deletes the product ONLY if it has no transactions. Products with transaction history cannot be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await message(() async {
      final result =
          await api.request('DELETE', '/api/admin/products/${product['id']}');
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
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
    final criteria = (report?['acceptance_criteria'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
    final stages = (report?['stress_stages'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        <Map<String, dynamic>>[];
    final sql = report?['previously_verified_sqlserver_concurrency'];
    final sqlEvidence = sql is Map<String, dynamic> ? sql : null;
    final summary = report?['summary'];
    final counts =
        summary is Map<String, dynamic> ? summary : <String, dynamic>{};

    Color statusColor(String value) => value == 'PASS'
        ? Colors.green.shade700
        : value == 'FAIL'
            ? Colors.red.shade700
            : Colors.orange.shade800;
    Widget statusChip(String status) => Text(status,
        style: TextStyle(
            color: statusColor(status),
            fontWeight: FontWeight.bold,
            fontSize: 12));
    String readable(String name) =>
        name.replaceFirst(RegExp(r'^test_'), '').replaceAll('_', ' ');
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                const Expanded(
                    child: Text('Question 5 — Testing Report',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close'),
              ]),
              Expanded(
                  child: ListView(children: [
                Text(
                    'Last generated: ${report?['generated_at'] ?? 'No report'}',
                    style: const TextStyle(fontSize: 12)),
                if (failure != null)
                  Text('Report error: $failure',
                      style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  Chip(label: Text('PASS ${counts['passed'] ?? 0}')),
                  Chip(label: Text('FAIL ${counts['failed'] ?? 0}')),
                  Chip(label: Text('NOT RUN ${counts['not_run'] ?? 0}')),
                ]),
                section('Acceptance criteria — Question 5'),
                if (criteria.isEmpty)
                  const Text(
                      'AC mapping not available. Update scripts/run_tests.py and run the tests again.'),
                ...criteria.map((ac) => Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        '${ac['id']} — ${ac['requirement']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                                statusChip('${ac['status'] ?? 'NOT VERIFIED'}'),
                              ]),
                              const SizedBox(height: 5),
                              Text('${ac['note'] ?? ''}',
                                  style: const TextStyle(fontSize: 12)),
                              if (ac['sqlserver_concurrency_evidence'] != null)
                                Text(
                                    'SQL Server evidence: ${ac['sqlserver_concurrency_evidence']}',
                                    style: const TextStyle(fontSize: 12)),
                            ])))),
                section('Automated test suites'),
                ...suites.map((suite) {
                  final cases = (suite['test_cases'] as List?)
                          ?.whereType<Map<String, dynamic>>()
                          .toList() ??
                      <Map<String, dynamic>>[];
                  final name = '${suite['name'] ?? 'Unnamed suite'}';
                  final status = '${suite['status'] ?? 'NOT RUN'}';
                  return Card(
                      child: ExpansionTile(
                    title: Row(children: [
                      Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      statusChip(status),
                    ]),
                    subtitle: Text(
                        cases.isNotEmpty
                            ? '${suite['passed']} passed · ${suite['failed']} failed · ${suite['skipped']} skipped'
                            : '${suite['details'] ?? ''}',
                        style: const TextStyle(fontSize: 12)),
                    children: [
                      if (cases.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                                'No individual test-case results recorded for this suite.')),
                      ...cases.map((test) => ListTile(
                            dense: true,
                            title: Text(readable('${test['name'] ?? ''}')),
                            subtitle: test['message'] == null ||
                                    '${test['message']}'.isEmpty
                                ? null
                                : Text('${test['message']}'),
                            trailing:
                                statusChip('${test['status'] ?? 'UNKNOWN'}'),
                          )),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('${suite['details'] ?? ''}',
                                  style: const TextStyle(fontSize: 11)))),
                    ],
                  ));
                }),
                section('Load test — GET /api/products (read-only)'),
                if (stages.isEmpty)
                  const Text('Stage details not available for this run.'),
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
                    trailing:
                        statusChip(stage['pass'] == true ? 'PASS' : 'FAIL'),
                  );
                }),
                section(
                    'SQL Server concurrency — separate previous verification'),
                if (sqlEvidence == null)
                  const Text(
                      'No previous SQL Server concurrency result available.'),
                if (sqlEvidence != null) ...[
                  Text('Status: ${sqlEvidence['status']} · '
                      '${sqlEvidence['passed'] ?? '?'} passed, '
                      '${sqlEvidence['failed'] ?? '?'} failed'),
                  const Text('Not re-executed by Run All Test.',
                      style: TextStyle(fontSize: 12)),
                  ...((sqlEvidence['test_cases'] as List?)
                              ?.whereType<Map<String, dynamic>>() ??
                          <Map<String, dynamic>>[])
                      .map((c) => ListTile(
                          dense: true,
                          title: Text(
                              '${c['test_case'] ?? c['name'] ?? 'Test case'}'),
                          subtitle: Text('${c['expected_result'] ?? ''}'),
                          trailing: statusChip(
                              '${c['testing_status'] ?? c['status'] ?? 'UNKNOWN'}'))),
                ],
                const SizedBox(height: 12),
                const Text(
                    'Scope: Mandai Question 5 only. Mocked API contracts do not prove '
                    'a full browser journey. SQL Server write tests are executed separately.',
                    style: TextStyle(fontSize: 12)),
              ])),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _runAllTestsFromFrontend();
                    },
                    child: const Text('Run All Test')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
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
              if (value.startsWith('Running'))
                const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(value),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close (tests continue)'))
        ],
      ),
    ));
    try {
      for (var i = 0; i < 600; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final result =
            await api.request('GET', '/api/admin/testing/run-all/status');
        if (result is! Map) continue;
        final state = result['state']?.toString() ?? 'unknown';
        if (state == 'completed' || state == 'failed') {
          progress.value = 'Test run $state';
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Run All Test: $state. Open Testing summary for details.')),
          );
          return;
        }
      }
      progress.value = 'Test is still running; check the Testing summary.';
    } catch (error) {
      progress.value = 'Unable to read progress: $error';
    }
  }

  Widget _inventoryView() {
    final isAdmin = api.role == 'admin';
    final categories = <String>{
      'All',
      ..._catalogCategories,
      ...products.map((p) => (p['category'] ?? 'Merchandise').toString())
    }.toList();
    final chosenCategory =
        categories.contains(selectedCategory) ? selectedCategory : 'All';
    // Server-side filters and sorting are applied before each page is returned.
    final visible = products.cast<Map<String, dynamic>>();
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
      },
    );
    final active = _adminInventoryStats?['active'] ?? '—';
    final stock = _adminInventoryStats?['stock'] ?? '—';
    final total = _adminInventoryStats?['total'] ?? '—';
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
          child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification &&
                    notification.metrics.extentAfter < 650 &&
                    _catalogHasMore &&
                    !_catalogLoadingMore &&
                    !busy) {
                  _fetchNextCatalogPage();
                }
                return false;
              },
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF174D3C),
                                Color(0xFF29775B)
                              ]),
                              borderRadius: BorderRadius.circular(24)),
                          child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          foregroundColor:
                                              const Color(0xFF146C55)),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add product')),
                              ])),
                      const SizedBox(height: 22),
                      if (isAdmin) ...[
                        if (narrow) ...[
                          Row(children: [
                            _metric('Products', '$total',
                                Icons.inventory_2_outlined),
                            _metric(
                                'Active', '$active', Icons.check_circle_outline)
                          ]),
                          Row(children: [
                            _metric(
                                'Stock units', '$stock', Icons.widgets_outlined)
                          ]),
                        ] else
                          Row(children: [
                            _metric('Products', '$total',
                                Icons.inventory_2_outlined),
                            _metric('Active', '$active',
                                Icons.check_circle_outline),
                            _metric('Stock units', '$stock',
                                Icons.widgets_outlined),
                          ]),
                        const SizedBox(height: 14),
                      ],
                      if (!wide)
                        Align(
                            alignment: Alignment.centerLeft,
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
                                style:
                                    const TextStyle(color: Color(0xFFB42318)))),
                      if (busy) const LinearProgressIndicator(),
                      const SizedBox(height: 10),
                    ])),
                // Desktop: keep filters in the left sidebar, beside the
                // lazily built product grid. Mobile retains its filter drawer.
                if (wide)
                  SliverCrossAxisGroup(slivers: [
                    SliverCrossAxisExpanded(
                        flex: 1, sliver: SliverToBoxAdapter(child: filters)),
                    SliverCrossAxisExpanded(
                        flex: 5,
                        sliver: SliverPadding(
                            padding: const EdgeInsets.only(left: 16, top: 12),
                            sliver: SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                    (ctx, i) => _productCard(visible[i]),
                                    childCount: visible.length),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cols,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                        mainAxisExtent: 390)))),
                  ])
                else
                  SliverPadding(
                      padding: const EdgeInsets.only(top: 12),
                      sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _productCard(visible[i]),
                              childCount: visible.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 390))),
                if (visible.isEmpty && !busy)
                  const SliverToBoxAdapter(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No matching products found.')))),
                if (_catalogHasMore)
                  SliverToBoxAdapter(
                      child: Center(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _catalogLoadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton(
                                      onPressed: _fetchNextCatalogPage,
                                      child:
                                          const Text('Load more products'))))),
                if (_catalogPageError != null)
                  SliverToBoxAdapter(
                      child: TextButton(
                          onPressed: _fetchNextCatalogPage,
                          child: Text(
                              'Retry loading products: $_catalogPageError'))),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                // Footer is part of the scroll content, never a fixed bottom overlay.
                SliverToBoxAdapter(
                    child: StoreFooter(
                  onRunConcurrencyTests:
                      api.role == 'admin' ? _openConcurrencyTests : null,
                  onTestingSummary:
                      api.role == 'admin' ? _openTestingSummary : null,
                )),
              ])));
    });
  }

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
}
