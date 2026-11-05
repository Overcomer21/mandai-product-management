part of '../main.dart';

// Extracted from Shell without changing application behaviour.
extension _ShellCustomer on _ShellState {
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

  void _switchCustomerTab(int tab) {
    // Admin may browse the dashboard/account, but not customer transactions.
    if (api.role == 'admin' && (tab == 1 || tab == 2)) return;
    _updateState(() => customerTab = tab);
    if (tab == 2) _loadOrders();
    if (tab == 3) _loadAccount();
  }

  Future<void> _loadAccount() async {
    final tokenAtRequest = api.token;
    if (tokenAtRequest == null || _accountLoading) return;
    _updateState(() {
      _accountLoading = true;
      _accountError = null;
    });
    try {
      final result = await api.request('GET', '/api/account/me');
      if (!mounted || api.token != tokenAtRequest) return;
      _updateState(
          () => _accountProfile = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (!mounted || api.token != tokenAtRequest) return;
      _updateState(() => _accountError = '$e');
    } finally {
      if (mounted && api.token == tokenAtRequest) {
        _updateState(() => _accountLoading = false);
      }
    }
  }

  Future<void> _loadOrders() async {
    _updateState(() => ordersBusy = true);
    try {
      final result = await api.request('GET', '/api/orders/my/details');
      if (mounted) _updateState(() => myOrders = result as List<dynamic>);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load orders: $e')));
      }
    } finally {
      if (mounted) _updateState(() => ordersBusy = false);
    }
  }

  bool _addCart(Map<String, dynamic> p, {int quantity = 1}) {
    if (api.token == null) {
      _updateState(() => _showLoginPage = true);
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

  Widget _cartView() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Shopping cart',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _ShellState.forest)),
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
                              style: const TextStyle(
                                  color: _ShellState.evergreen)),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                onPressed: entry.value > 1
                                    ? () => _updateState(() {
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
                                    ? () => _updateState(() {
                                          cart[entry.key] = entry.value + 1;
                                          pendingCheckoutKey = null;
                                          _updateCartBadge();
                                        })
                                    : null,
                                icon: const Icon(Icons.add_circle_outline)),
                            IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _updateState(() {
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
          _amountLine('Delivery fee', _ShellState.deliveryFee),
          const Divider(),
          _amountLine('Total', _subtotal + _ShellState.deliveryFee, bold: true),
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
                                style: TextStyle(
                                    fontSize: 12, color: _ShellState.muted)),
                            const SizedBox(height: 12),
                            const InputDecorator(
                              decoration: InputDecoration(
                                  labelText: 'Redeem points (coming soon)',
                                  prefixIcon: Icon(Icons.stars_outlined)),
                              child: Text('Not available in this demo',
                                  style: TextStyle(color: _ShellState.muted)),
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
                                    title: Text(
                                        'Stripe secure online payment (Sandbox)'),
                                    value: 'stripe_test'),
                              ]),
                            ),
                            if (method != 'stripe_test')
                              CheckboxListTile(
                                  value: decline,
                                  onChanged: (v) =>
                                      update(() => decline = v ?? false),
                                  title: const Text(
                                      'Simulate declined payment (test)')),
                            _amountLine('Subtotal', _subtotal),
                            _amountLine('Delivery', _ShellState.deliveryFee),
                            _amountLine(
                                'Total', _subtotal + _ShellState.deliveryFee,
                                bold: true),
                            Text(
                                method == 'stripe_test'
                                    ? 'Sandbox: card details are entered on Stripe. Payment is confirmed only after a verified webhook.'
                                    : 'Payment is simulated. No card numbers are collected; Luhn verification uses synthetic test data only.',
                                style: const TextStyle(
                                    fontSize: 12, color: _ShellState.muted))
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Back')),
                    FilledButton(
                        onPressed: checkoutBusy
                            ? null
                            : () => Navigator.pop(dialogCtx, true),
                        child: Text(method == 'stripe_test'
                            ? 'Continue to Stripe'
                            : 'Confirm & pay'))
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
    _updateState(() => checkoutBusy = true);
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
      _updateState(() {
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
      if (mounted) _updateState(() => checkoutBusy = false);
    }
  }

  // Browser return is a navigation hint. Always ask our authenticated backend
  // to resolve the Stripe Session to the owning order and verify it with Stripe.

  // A key is tied to one exact checkout payload. Never reuse it for
  // different cart contents or delivery address, including after a timeout.
  bool _sameStripeCheckoutPayload(String address) {
    final saved = _stripeCheckoutItemsSnapshot;
    if (saved == null || _stripeCheckoutAddressSnapshot != address ||
        saved.length != cart.length) {
      return false;
    }
    for (final item in cart.entries) {
      if (saved[item.key] != item.value) return false;
    }
    return true;
  }

  // Forget a key only after the matching order has a confirmed terminal state.
  // This must not clear an unrelated checkout started from the same app state.
  void _clearTrackedStripeCheckout(int orderId) {
    if (_stripeCheckoutOrderId != orderId) return;
    _stripeCheckoutKey = null;
    _stripeCheckoutOrderId = null;
    _stripeCheckoutItemsSnapshot = null;
    _stripeCheckoutAddressSnapshot = null;
  }

  Future<void> _onStripeReturn(String sessionId) async {
    if (!mounted) return;
    if (api.token == null || api.role != 'user') {
      _pendingStripeReturnSession = sessionId;
      _updateState(() => _showLoginPage = true);
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
      _updateState(() => customerTab = 2);
      final paid = verified['order_status'] == 'completed' &&
          verified['payment_status'] == 'approved_test';
      if (paid) {
        _updateState(() {
          cart.clear();
          _clearTrackedStripeCheckout(orderId);
          _updateCartBadge();
        });
      }
      if (verified['order_status'] == 'expired') {
        _updateState(() => _clearTrackedStripeCheckout(orderId));
      }
      // A paid or expired session changes inventory availability.
      // Refresh the catalogue so cart quantity controls use server stock.
      if (paid || verified['order_status'] == 'expired') {
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
        content: Text(
            'Unable to verify returned payment. Check Orders; do not pay again. $e'),
      ));
    }
  }

  Future<void> _checkoutWithStripe() async {
    if (api.token == null ||
        api.role != 'user' ||
        checkoutBusy ||
        cart.isEmpty) {
      return;
    }
    // A retry may reuse an idempotency key ONLY with its original payload.
    // On uncertainty, verify the previous order instead of starting a new one.
    final address = addressController.text.trim();
    if (_stripeCheckoutKey != null && !_sameStripeCheckoutPayload(address)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cart or delivery address changed during a previous Stripe checkout. Verify or cancel that order in My Purchases before starting another payment.'),
      ));
      _updateState(() => customerTab = 2);
      await _loadOrders();
      return;
    }
    if (_stripeCheckoutOrderId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An existing Stripe checkout must be verified or cancelled in My Purchases before starting another payment.'),
      ));
      _updateState(() => customerTab = 2);
      await _loadOrders();
      return;
    }
    _updateState(() => checkoutBusy = true);
    if (_stripeCheckoutKey == null) {
      _stripeCheckoutKey = StripeCheckoutClient.newIdempotencyKey();
      _stripeCheckoutOrderId = null;
      _stripeCheckoutItemsSnapshot = Map<int, int>.from(cart);
      _stripeCheckoutAddressSnapshot = address;
    }
    final client = StripeCheckoutClient(apiBase: apiBase, token: api.token!);
    try {
      final result = await client.createSession(
        items: cart.entries
            .map((e) => {'product_id': e.key, 'quantity': e.value})
            .toList(),
        deliveryAddress: addressController.text.trim(),
        idempotencyKey: _stripeCheckoutKey!,
      );
      if (!mounted) return;
      final orderId = (result['order_id'] as num).toInt();
      _stripeCheckoutOrderId = orderId;
      // The server has committed the stock reservation at this point.
      // Refresh the visible stock before switching to hosted checkout.
      await load();
      if (!mounted) return;
      final checkoutUrl = (result['checkout_url'] ?? '').toString();
      if (checkoutUrl.isNotEmpty) await client.openStripe(checkoutUrl);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Stripe payment status'),
                content: Text(
                    'Invoice ${result['invoice_number']}\n\nComplete payment in Stripe Checkout, then select Check payment status.\n\nDo not pay twice. Returning from the browser does not confirm payment.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Check later')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Check payment status')),
                ],
              ));
      if (!mounted) return;
      final status = await client.reconcile(orderId);
      if (!mounted) return;
      if (status['payment_status'] == 'approved_test' &&
          status['order_status'] == 'completed') {
        _updateState(() {
          cart.clear();
          _clearTrackedStripeCheckout(orderId);
          customerTab = 2;
          _updateCartBadge();
        });
        await load();
        await _loadOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Stripe sandbox payment verified: ${status['invoice_number']}')));
        }
      } else {
        if (status['order_status'] == 'expired') {
          _updateState(() => _clearTrackedStripeCheckout(orderId));
          await load();
        }
        // Keep cart unchanged; order remains pending or requires reconciliation.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Payment status: ${status['payment_status']}. Invoice: ${status['invoice_number']}. Check Orders before retrying.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Stripe payment: $error. Do not start another payment until status is checked.')));
      }
    } finally {
      if (mounted) _updateState(() => checkoutBusy = false);
    }
  }

  // Keep existing cards and scroll offset when filters change.

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
        _updateState(() => _clearTrackedStripeCheckout(orderId));
        await load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Payment confirmed: ${verified['invoice_number']}')));
        return;
      }
      if (verified['order_status'] == 'expired' ||
          verified['stripe_checkout_status'] == 'expired') {
        // A confirmed release has committed to SQL: reload cached catalogue.
        if (verified['order_status'] == 'expired') {
          _updateState(() => _clearTrackedStripeCheckout(orderId));
          await load();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Checkout expired. Reserved stock has been released when cancellation is finalized.')));
        return;
      }
      if (verified['stripe_payment_status'] == 'paid' ||
          verified['attempt_status'] != 'pending' ||
          verified['stripe_checkout_status'] != 'open' ||
          verified['stripe_payment_status'] != 'unpaid') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This checkout needs verification. Do not pay again or resume it.')));
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Resume payment')),
          ],
        ),
      );
      if (resumeNow == true) {
        await client.openStripe('${resume['checkout_url']}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Stripe verification: $e. Do not pay again until status is checked.'),
        ));
      }
    }
  }

  Future<void> _cancelPendingStripeOrder(int orderId) async {
    if (api.token == null || api.role != 'user') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('Cancel Order #$orderId? The Stripe payment session will be closed if it is still unpaid. Stock is restored only after Stripe confirms expiration.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final client = StripeCheckoutClient(apiBase: apiBase, token: api.token!);
      final cancelled = await client.cancelOrder(orderId);
      if (!mounted) return;
      // Only refresh inventory as released after the backend confirms expiry.
      if (cancelled['status'] != 'expired') {
        throw StateError('Cancellation was not confirmed by the server');
      }
      _updateState(() => _clearTrackedStripeCheckout(orderId));
      await load();
      if (!mounted) return;
      await _loadOrders();
      if (!mounted) return;
      // Keep cart items/quantities: cancellation releases reservation, not cart.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Checkout cancelled. Stock and orders have been refreshed.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unable to cancel order: $e'),
      ));
      await _loadOrders();
    }
  }

  Widget _customerOrdersView() {
    final displayed = myOrders.where((order) {
      final pending = order is Map && order['status'] == 'pending_payment';
      return ordersFilter == 0 || (ordersFilter == 1 && pending);
    }).toList();
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('My purchases',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: _ShellState.forest)),
        const SizedBox(height: 8),
        const Text('Order history from the secure backend.',
            style: TextStyle(color: _ShellState.muted)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('All Orders'),
              selected: ordersFilter == 0,
              onSelected: (_) => _updateState(() => ordersFilter = 0)),
          ChoiceChip(label: const Text('To Pay'),
              selected: ordersFilter == 1,
              onSelected: (_) {
                _updateState(() => ordersFilter = 1);
                _loadOrders();
              }),
        ]),
        if (ordersBusy) const LinearProgressIndicator(),
        if (!ordersBusy && displayed.isEmpty)
          Padding(padding: const EdgeInsets.all(28),
              child: Center(child: Text(ordersFilter == 1
                  ? 'No orders awaiting payment.' : 'No purchases yet.'))),
        ...displayed.map((order) => Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_rounded,
                color: _ShellState.evergreen),
            title: Text('Order #${order['id']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${order['status']} • ${order['payment_status']}'),
                if (order['status'] == 'pending_payment')
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    TextButton(
                      onPressed: () => _verifyOrResumeStripe((order['id'] as num).toInt()),
                      child: const Text('Verify / Resume Stripe'),
                    ),
                    TextButton(
                      onPressed: () => _cancelPendingStripeOrder((order['id'] as num).toInt()),
                      child: const Text('Cancel Order'),
                    ),
                  ]),
              ],
            ),
            trailing: Text('S\$${order['total_amount']}',
                style: const TextStyle(fontWeight: FontWeight.w700,
                    color: _ShellState.forest)),
          ),
        )),
      ]),
    );
  }

  Widget _accountView() {
    if (_accountLoading && _accountProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_accountError != null && _accountProfile == null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
    _updateState(() {
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
}
