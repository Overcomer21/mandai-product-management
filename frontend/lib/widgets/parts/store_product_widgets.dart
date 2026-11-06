part of '../store_widgets.dart';


class StoreProductDetail extends StatefulWidget {
  const StoreProductDetail(
      {super.key,
      required this.product,
      required this.image,
      required this.onAddToCart,
      required this.onBuyNow});
  final Map<String, dynamic> product;
  final Widget image;
  final ValueChanged<int> onAddToCart, onBuyNow;
  @override
  State<StoreProductDetail> createState() => _StoreProductDetailState();
}

class _StoreProductDetailState extends State<StoreProductDetail> {
  int quantity = 1;
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final available = stock > 0 && p['is_active'] != false;
    final wide = MediaQuery.sizeOf(context).width > 800;
    final media = AspectRatio(
        aspectRatio: 1.05,
        child: ColoredBox(color: const Color(0xFFEAF4EC), child: widget.image));
    final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${p['name']}',
              softWrap: true,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: storeForest)),
          const SizedBox(height: 14),
          Text('S\$${p['price']}',
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: storeGreen)),
          const SizedBox(height: 12),
          Text('${p['category'] ?? 'Merchandise'} • $stock in stock'),
          const SizedBox(height: 18),
          Text('${p['description'] ?? ''}'),
          const SizedBox(height: 20),
          Row(children: [
            const Text('Quantity'),
            const SizedBox(width: 12),
            IconButton(
                onPressed:
                    quantity > 1 ? () => setState(() => quantity--) : null,
                icon: const Icon(Icons.remove_circle_outline)),
            Text('$quantity'),
            IconButton(
                onPressed: available && quantity < stock
                    ? () => setState(() => quantity++)
                    : null,
                icon: const Icon(Icons.add_circle_outline)),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
                onPressed:
                    available ? () => widget.onAddToCart(quantity) : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Add to Cart')),
            FilledButton.icon(
                onPressed: available ? () => widget.onBuyNow(quantity) : null,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Buy Now')),
          ]),
        ]);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: SingleChildScrollView(
                padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 420 ? 8 : 20),
                child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(
                            MediaQuery.sizeOf(context).width < 420 ? 12 : 20),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Expanded(child: media),
                                    const SizedBox(width: 28),
                                    Expanded(child: details)
                                  ])
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    media,
                                    const SizedBox(height: 20),
                                    details
                                  ]))))));
  }
}
