import 'dart:async';
import 'package:flutter/material.dart';

/// Builds the destination underneath an opaque splash. The overlay fades only
/// when both the minimum duration and the destination's first load complete.
/// No navigation replacement and no intermediate/partially loaded page flash.
class MandaiSplashGate extends StatefulWidget {
  const MandaiSplashGate(
      {super.key,
      required this.builder,
      this.duration = const Duration(seconds: 5)});
  final Widget Function(VoidCallback onLandingReady) builder;
  final Duration duration;

  @override
  State<MandaiSplashGate> createState() => _MandaiSplashGateState();
}

class _MandaiSplashGateState extends State<MandaiSplashGate> {
  Timer? _timer;
  bool _minimumElapsed = false;
  bool _landingReady = false;
  bool _fading = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    // Start counting only AFTER the first splash frame was rendered. A timer
    // started during initState can expire before the splash is visible on
    // slower Android devices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(widget.duration, () {
        if (!mounted) return;
        _minimumElapsed = true;
        _tryReveal();
      });
    });
  }

  void _onLandingReady() {
    if (!mounted || _landingReady) return;
    _landingReady = true;
    _tryReveal();
  }

  void _tryReveal() {
    if (!mounted || _fading || !_minimumElapsed || !_landingReady) return;
    setState(() => _fading = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.builder(_onLandingReady),
        if (!_removed)
          Positioned.fill(
              child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
            onEnd: () {
              if (mounted && _fading && !_removed) {
                setState(() => _removed = true);
              }
            },
            child: const MandaiSplashScreen(),
          )),
      ]);
}

class MandaiSplashScreen extends StatelessWidget {
  const MandaiSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 480;
    return Scaffold(
      backgroundColor: const Color(0xFF174D3C),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Mandai WildLife',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: isNarrow ? 30 : 42,
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.asset('assets/splash/panda.jpg',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE8F2EB),
                            child: Icon(Icons.pets,
                                size: 96, color: Color(0xFF174D3C)))))),
            const SizedBox(height: 20),
            const Text(
                '🇸🇬  Discover Mandai WildLife: Where the Ordinary Becomes Extraordinary',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4)),
            const SizedBox(height: 24),
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5)),
          ]),
        ),
      ))),
    );
  }
}
