import 'package:flutter/material.dart';
import '../data/product.dart';

/// Zoomable image viewer; optional 360-degree *photo sequence* viewer.
/// A single photograph cannot provide a genuine 3D product model.
class ProductMediaViewer extends StatefulWidget {
  const ProductMediaViewer({super.key, required this.product});
  final Product product;
  @override
  State<ProductMediaViewer> createState() => _ProductMediaViewerState();
}

class _ProductMediaViewerState extends State<ProductMediaViewer> {
  final TransformationController _transformation = TransformationController();
  int _frame = 0;
  int _quarterTurns = 0;
  final GlobalKey _viewerKey = GlobalKey();
  List<String> get _frames => widget.product.spinFrames;

  String _url(String value) {
    final parsed = Uri.tryParse(value.trim());
    const apiBase = String.fromEnvironment('API_BASE',
        defaultValue: 'http://127.0.0.1:8000');
    final base = Uri.tryParse(apiBase);
    if (parsed != null && parsed.hasScheme) {
      if ((parsed.host == 'localhost' || parsed.host == '127.0.0.1') &&
          base != null &&
          base.hasAuthority &&
          base.host != 'localhost' &&
          base.host != '127.0.0.1') {
        return parsed.replace(host: base.host, port: base.port).toString();
      }
      return value;
    }
    return base
            ?.resolve(value.startsWith('/') ? value : '/$value')
            .toString() ??
        value;
  }

  void _zoom(double factor) {
    final matrix = _transformation.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(1.0, 4.0).toDouble();
    final actualFactor = targetScale / currentScale;
    if ((actualFactor - 1.0).abs() < 0.001) return;
    final viewport = _viewerKey.currentContext?.size ?? const Size(300, 240);
    final focalPoint = Offset(viewport.width / 2, viewport.height / 2);
    // Preserve the point in the image currently underneath the viewport center.
    final translated = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0.0, 1.0)
      ..scaleByDouble(actualFactor, actualFactor, 1.0, 1.0)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0.0, 1.0);
    _transformation.value = translated * matrix;
  }

  void _rotate() {
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
  }

  void _resetView() {
    _transformation.value = Matrix4.identity();
    setState(() => _quarterTurns = 0);
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _frames;
    final url = images.isNotEmpty
        ? images[_frame.clamp(0, images.length - 1)]
        : widget.product.imageUrl;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Text(widget.product.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            Flexible(
                child: AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: const Color(0xFFF0F4F1),
                  child: InteractiveViewer(
                    key: _viewerKey,
                    transformationController: _transformation,
                    minScale: 1,
                    maxScale: 4,
                    child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: url.isEmpty
                            ? const Center(
                                child: Icon(Icons.image_outlined, size: 72))
                            : Image.network(_url(url),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Text('Image unavailable')))),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(0.8),
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
                  onPressed: () => _zoom(1.25),
                  icon: const Icon(Icons.zoom_in)),
            ]),
            if (images.length > 1) ...[
              const Text(
                  '360° photo rotation — drag the slider to change view'),
              Slider(
                value: _frame.toDouble(),
                min: 0,
                max: (images.length - 1).toDouble(),
                divisions: images.length - 1,
                label: 'Frame ${_frame + 1}/${images.length}',
                onChanged: (value) {
                  setState(() {
                    _frame = value.round();
                    _quarterTurns = 0;
                  });
                  _transformation.value = Matrix4.identity();
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
