part of '../store_widgets.dart';

/// Limited to existing product attributes: category, price, availability.
class StoreFilterPanel extends StatelessWidget {
  const StoreFilterPanel(
      {super.key,
      required this.categories,
      required this.category,
      required this.onCategory,
      required this.inStockOnly,
      required this.onInStockOnly,
      required this.sort,
      required this.onSort});
  final List<String> categories;
  final String category, sort;
  final ValueChanged<String> onCategory, onSort;
  final bool inStockOnly;
  final ValueChanged<bool> onInStockOnly;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('All Categories',
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: storeForest)),
            const SizedBox(height: 10),
            ...categories.map((c) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(c,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c == category ? storeGreen : null,
                          fontWeight: c == category
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  selected: c == category,
                  onTap: () => onCategory(c),
                )),
            const Divider(),
            const Text('Search filter',
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: storeForest)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('In stock only'),
                value: inStockOnly,
                onChanged: (v) => onInStockOnly(v ?? false)),
            const SizedBox(height: 8),
            const Text('Sort by',
                style: TextStyle(fontWeight: FontWeight.w700)),
            DropdownButton<String>(
                isExpanded: true,
                value: sort,
                items: const [
                  DropdownMenuItem(value: 'Default', child: Text('Default')),
                  DropdownMenuItem(
                      value: 'Price low', child: Text('Price: low to high')),
                  DropdownMenuItem(
                      value: 'Price high', child: Text('Price: high to low')),
                  DropdownMenuItem(value: 'Name', child: Text('Name')),
                ],
                onChanged: (v) {
                  if (v != null) onSort(v);
                }),
          ],
        ),
      ));
}

class StoreProductCard extends StatelessWidget {
  const StoreProductCard(
      {super.key,
      required this.product,
      required this.image,
      required this.onOpen});
  final Map<String, dynamic> product;
  final Widget image;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final available = product['is_active'] != false &&
        ((product['stock'] as num?)?.toInt() ?? 0) > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child:
                      ColoredBox(color: const Color(0xFFEAF4EC), child: image)),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${product['category'] ?? 'Merchandise'}'
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF607B6D))),
                      const SizedBox(height: 5),
                      Text('${product['name'] ?? 'Product'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: storeForest)),
                      const SizedBox(height: 7),
                      Text('S\$${product['price'] ?? '0.00'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: storeGreen)),
                      const SizedBox(height: 4),
                      Text(
                          available
                              ? '${product['stock']} in stock'
                              : 'Unavailable',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF607B6D))),
                    ],
                  )),
            ],
          )),
    );
  }
}
