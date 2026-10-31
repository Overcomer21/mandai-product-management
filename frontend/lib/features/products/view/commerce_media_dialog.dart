import 'package:flutter/material.dart';

/// Shared product image viewer for customer and admin in the active main.dart app.
/// A 360-degree multi-angle view requires multiple actual photographs.
class CommerceMediaDialog extends StatefulWidget {
  const CommerceMediaDialog(
      {super.key,
      required this.product,
      required this.apiBase,
      required this.fallbackAsset});
  final Map<String, dynamic> product;
  final String apiBase;
  final String fallbackAsset;

  @override
  State<CommerceMediaDialog> createState() => _CommerceMediaDialogState();
}

class _CommerceMediaDialogState extends State<CommerceMediaDialog> {
  final TransformationController _transform = TransformationController();
  int _index = 0;
  int _quarterTurns = 0;
  final GlobalKey _viewerKey = GlobalKey();

  String _url(String raw) {
    final value = raw.trim();
    final base = Uri.tryParse(widget.apiBase);
    final parsed = Uri.tryParse(value.replaceAll(String.fromCharCode(92), '/'));
    if (base == null || !base.hasAuthority || parsed == null) return value;
    if (parsed.hasScheme &&
        (parsed.scheme == 'https' || parsed.scheme == 'http')) {
      if (parsed.host == 'localhost' ||
          parsed.host == '127.0.0.1' ||
          parsed.host == '10.0.2.2') {
        return base
            .resolveUri(Uri(
                path: parsed.path,
                query: parsed.hasQuery ? parsed.query : null))
            .toString();
      }
      return parsed.toString();
    }
    if (value.startsWith('//')) return '${base.scheme}:$value';
    return base.resolve(value.startsWith('/') ? value : '/$value').toString();
  }

  List<String> get _frames {
    final raw = (widget.product['spin_image_urls'] ?? '').toString();
    return raw
        .split(RegExp(r'\r?\n|,'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _scale(double factor) {
    final matrix = _transform.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(1.0, 5.0).toDouble();
    final actualFactor = targetScale / currentScale;
    if ((actualFactor - 1.0).abs() < 0.001) return;
    final viewport = _viewerKey.currentContext?.size ?? const Size(300, 240);
    final focalPoint = Offset(viewport.width / 2, viewport.height / 2);
    // Preserve the point in the image currently underneath the viewport center.
    final translated = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0.0, 1.0)
      ..scaleByDouble(actualFactor, actualFactor, 1.0, 1.0)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0.0, 1.0);
    _transform.value = translated * matrix;
  }

  void _rotate() {
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
  }

  void _resetView() {
    _transform.value = Matrix4.identity();
    setState(() => _quarterTurns = 0);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    final single = (widget.product['image_url'] ?? '').toString().trim();
    final current =
        frames.isEmpty ? single : frames[_index.clamp(0, frames.length - 1)];
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      (widget.product['name'] ?? 'Product image').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            Flexible(
                child: AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: const Color(0xFFF1F5F2),
                  child: InteractiveViewer(
                    key: _viewerKey,
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 5,
                    child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: current.isEmpty
                            ? const Center(
                                child: Icon(Icons.image_outlined, size: 64))
                            : Image.network(_url(current), fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                debugPrint(
                                    'Product viewer image failed: ${_url(current)} — $error');
                                return Image.asset(widget.fallbackAsset,
                                    fit: BoxFit.contain);
                              })),
                  ),
                ),
              ),
            )),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _scale(.8),
                  icon: const Icon(Icons.zoom_out)),
              IconButton(
                  tooltip: 'Reset zoom',
                  onPressed: _resetView,
                  icon: const Icon(Icons.center_focus_strong)),
              IconButton(
                  tooltip: 'Rotate 90 degrees',
                  onPressed: _rotate,
                  icon: const Icon(Icons.rotate_right)),
              IconButton(
                  tooltip: 'Zoom in',
                  onPressed: () => _scale(1.25),
                  icon: const Icon(Icons.zoom_in)),
            ]),
            if (frames.length > 1) ...[
              const Text('360° photo sequence — move slider to change angle'),
              Slider(
                value: _index.toDouble(),
                min: 0,
                max: (frames.length - 1).toDouble(),
                divisions: frames.length - 1,
                label: '${_index + 1}/${frames.length}',
                onChanged: (value) {
                  setState(() {
                    _index = value.round();
                    _quarterTurns = 0;
                  });
                  _transform.value = Matrix4.identity();
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
