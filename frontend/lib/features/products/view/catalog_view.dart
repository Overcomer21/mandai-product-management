import 'package:flutter/material.dart';

import '../../../core/widgets/metric_card.dart';
import '../data/product.dart';
import 'product_card.dart';

class CatalogView extends StatelessWidget {
  const CatalogView({
    super.key,
    required this.products,
    required this.admin,
    required this.loading,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onDeactivate,
    required this.onBuy,
  });

  final List<Product> products;
  final bool admin;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDeactivate;
  final ValueChanged<Product> onBuy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        const minCardWidth = 300.0;
        final width = constraints.maxWidth;
        final columns =
            ((width + gap) / (minCardWidth + gap)).floor().clamp(1, 4);
        final narrow = width < 660;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final cardHeight = 405.0 + (textScale > 1 ? (textScale - 1) * 45 : 0);

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF174D3C), Color(0xFF29775B)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 14,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'WILDLIFE MERCHANDISE',
                                style: TextStyle(
                                  color: Color(0xFFCAE5D2),
                                  fontSize: 11,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                admin
                                    ? 'Inventory dashboard'
                                    : 'Discover something wild',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (admin)
                            FilledButton.icon(
                              onPressed: onAdd,
                              icon: const Icon(Icons.add),
                              label: const Text('Add product'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (admin) ...[
                      Row(
                        children: [
                          MetricCard(
                            label: 'Products',
                            value: '${products.length}',
                            icon: Icons.inventory_2_outlined,
                          ),
                          MetricCard(
                            label: 'Active',
                            value:
                                '${products.where((p) => p.isActive).length}',
                            icon: Icons.check_circle_outline,
                          ),
                          if (!narrow)
                            MetricCard(
                              label: 'Stock',
                              value:
                                  '${products.fold<int>(0, (sum, p) => sum + p.stock)}',
                              icon: Icons.widgets_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            admin ? 'Product catalogue' : 'Explore merchandise',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh products',
                          onPressed: loading ? null : () => onRefresh(),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (loading) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (products.isEmpty && !loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No products found.')),
                )
              else
                SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: products[index],
                      admin: admin,
                      onEdit: onEdit,
                      onDeactivate: onDeactivate,
                      onBuy: onBuy,
                    ),
                    childCount: products.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    mainAxisExtent: cardHeight,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }
}
