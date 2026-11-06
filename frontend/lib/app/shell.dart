import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/widgets/status_chip.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/view/login_view.dart';
import '../features/products/bloc/product_bloc.dart';
import '../features/products/data/product.dart';
import '../features/products/data/product_repository.dart';
import '../features/products/view/catalog_view.dart';
import '../features/products/view/product_editor.dart';
import '../features/purchases/bloc/purchase_bloc.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  Future<void> _edit(BuildContext context, Product? product) async {
    final bloc = context.read<ProductBloc>();

    final input = await showDialog<ProductInput>(
      context: context,
      builder: (dialogContext) => ProductEditor(product: product),
    );

    if (!context.mounted) return;

    if (input != null) {
      bloc.add(ProductSaved(input, id: product?.id));
    }
  }

  Future<void> _buy(BuildContext context, Product product) async {
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product is out of stock')),
      );
      return;
    }

    final bloc = context.read<PurchaseBloc>();

    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _QuantityDialog(
        maxQuantity: product.stock,
      ),
    );

    if (!context.mounted) return;

    if (quantity != null) {
      bloc.add(PurchaseRequested(product.id, quantity));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            if (state.status == AuthStatus.authenticated) {
              context.read<ProductBloc>().add(
                    ProductsRequested(state.isAdmin),
                  );
            }
          },
        ),
        BlocListener<ProductBloc, ProductState>(
          listener: (context, state) {
            final message = state.error ?? state.notice;

            if (message != null && state.status != ProductStatus.loading) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
        ),
        BlocListener<PurchaseBloc, PurchaseState>(
          listener: (context, state) {
            if (state.status == PurchaseStatus.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.message ?? 'Purchase completed',
                  ),
                ),
              );

              final auth = context.read<AuthBloc>().state;

              context.read<ProductBloc>().add(
                    ProductsRequested(auth.isAdmin),
                  );
            } else if (state.status == PurchaseStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.message ?? 'Purchase failed',
                  ),
                ),
              );
            }
          },
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, auth) {
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F1E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.forest_rounded,
                      color: Color(0xFF146C55),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mandai Merchandise',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Technical assessment demo',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (auth.status == AuthStatus.authenticated) ...[
                  Center(
                    child: StatusChip(
                      label: auth.isAdmin ? 'Administrator' : 'Customer',
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => context.read<AuthBloc>().add(
                          const SignOutRequested(),
                        ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1300),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: auth.status != AuthStatus.authenticated
                      ? const LoginView()
                      : BlocBuilder<ProductBloc, ProductState>(
                          builder: (context, state) {
                            return CatalogView(
                              products: state.products,
                              admin: auth.isAdmin,
                              loading: state.status == ProductStatus.loading,
                              onRefresh: () async {
                                context.read<ProductBloc>().add(
                                      ProductsRequested(auth.isAdmin),
                                    );
                              },
                              onAdd: () => _edit(context, null),
                              onEdit: (product) => _edit(context, product),
                              onDelete: (product) async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Delete product?'),
                                    content: const Text(
                                      'This permanently deletes a product only if it has no transaction history. Products referenced by orders cannot be deleted.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(dialogContext, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  context.read<ProductBloc>().add(ProductDeleted(product.id));
                                }
                              },
                              onBuy: (product) => _buy(context, product),
                            );
                          },
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.maxQuantity});

  final int maxQuantity;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  int quantity = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Purchase merchandise'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$quantity'),
          IconButton(
            onPressed: quantity < widget.maxQuantity
                ? () => setState(() => quantity++)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, quantity),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
