import 'package:flutter/material.dart';

import '../../../core/widgets/status_chip.dart';
import '../data/product.dart';
import 'product_media_viewer.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.admin,
    required this.onEdit,
    required this.onDeactivate,
    required this.onBuy,
  });

  final Product product;
  final bool admin;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDeactivate;
  final ValueChanged<Product> onBuy;

  @override
  Widget build(BuildContext context) {
    final available = product.stock > 0 && product.isActive;
    final imageUrl = product.imageUrl.isNotEmpty
        ? product.imageUrl
        : (product.spinFrames.isEmpty ? '' : product.spinFrames.first);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: imageUrl.isEmpty
                  ? null
                  : () => showDialog<void>(
                        context: context,
                        builder: (_) => ProductMediaViewer(product: product),
                      ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  height: 154,
                  child: ColoredBox(
                    color: const Color(0xFFEAF4EC),
                    child: imageUrl.isEmpty
                        ? const Icon(Icons.pets_rounded,
                            size: 44, color: Color(0xFF52856C))
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child:
                                  Icon(Icons.broken_image_outlined, size: 36),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // This region may scroll at high accessibility text scaling,
            // keeping the action button visible and preventing RenderFlex overflow.
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: Color(0xFF768C7E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          'S\$${product.price}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF146C55),
                          ),
                        ),
                        StatusChip(
                          label: !product.isActive
                              ? 'Inactive'
                              : available
                                  ? '${product.stock} in stock'
                                  : 'Sold out',
                          positive: available,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (admin)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onEdit(product),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Deactivate product',
                    onPressed:
                        product.isActive ? () => onDeactivate(product) : null,
                    icon: const Icon(Icons.archive_outlined),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: available ? () => onBuy(product) : null,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Buy now'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
