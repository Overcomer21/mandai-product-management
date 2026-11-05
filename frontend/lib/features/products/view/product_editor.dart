import 'package:flutter/material.dart';

import '../data/product.dart';
import '../data/product_repository.dart';

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, this.product});

  final Product? product;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.product?.name ?? '',
  );

  late final TextEditingController _category = TextEditingController(
    text: widget.product?.category ?? 'Merchandise',
  );

  late final TextEditingController _description = TextEditingController(
    text: widget.product?.description ?? '',
  );

  late final TextEditingController _price = TextEditingController(
    text: widget.product?.price ?? '0.00',
  );

  late final TextEditingController _stock = TextEditingController(
    text: widget.product?.stock.toString() ?? '0',
  );

  late final TextEditingController _image = TextEditingController(
    text: widget.product?.imageUrl ?? '',
  );

  late final TextEditingController _spin = TextEditingController(
    text: widget.product?.spinImageUrls ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    _image.dispose();
    _spin.dispose();
    super.dispose();
  }

  String? _validateImageUrl(String? text) {
    final value = (text ?? '').trim();

    if (value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);

    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return 'Enter a valid image URL';
    }

    if (uri.scheme == 'https') {
      return null;
    }

    if (uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
      return null;
    }

    return 'Use HTTPS or localhost HTTP';
  }

  String? _validateSpinUrls(String? text) {
    final lines = (text ?? '').split(RegExp(r'\r?\n'));

    for (final line in lines) {
      final error = _validateImageUrl(line);

      if (error != null) {
        return error;
      }
    }

    return null;
  }

  String? _validatePrice(String? text) {
    final value = (text ?? '').trim();

    if (!RegExp(r'^\d{1,16}(\.\d{1,2})?$').hasMatch(value)) {
      return 'Enter a valid price (max 2 decimal places)';
    }

    final integerPart = BigInt.tryParse(value.split('.').first);

    if (integerPart == null || integerPart > BigInt.parse('9999999999999999')) {
      return 'Price exceeds the maximum value';
    }

    return null;
  }

  String? _validateStock(String? text) {
    final value = int.tryParse((text ?? '').trim());

    if (value == null || value < 0 || value > 2147483647) {
      return 'Enter a valid stock quantity';
    }

    return null;
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    Navigator.of(context).pop(
      ProductInput(
        name: _name.text.trim(),
        category: _category.text.trim(),
        description: _description.text.trim(),
        price: _price.text.trim(),
        stock: int.parse(_stock.text.trim()),
        isActive: widget.product?.isActive ?? true,
        imageUrl: _image.text.trim(),
        spinImageUrls: _spin.text.trim(),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: label,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final availableHeight = screenSize.height * 0.94;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: availableHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.product == null
                      ? 'Add merchandise'
                      : 'Edit merchandise',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(
                          'Product name',
                          _name,
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _field('Category', _category),
                        const SizedBox(height: 14),
                        _field(
                          'Description',
                          _description,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                'Price',
                                _price,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                validator: _validatePrice,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _field(
                                'Stock',
                                _stock,
                                keyboardType: TextInputType.number,
                                validator: _validateStock,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _field(
                          'Product image URL',
                          _image,
                          validator: _validateImageUrl,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          '360° photos — one URL per line (optional)',
                          _spin,
                          maxLines: 3,
                          validator: _validateSpinUrls,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
