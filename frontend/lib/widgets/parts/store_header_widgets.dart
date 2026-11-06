part of '../store_widgets.dart';

/// Visual-only membership tabs, matching the two-segment marketplace header.
/// Selection does not change authentication, pricing, checkout or API calls.
class _StoreMemberTabs extends StatefulWidget {
  const _StoreMemberTabs();

  @override
  State<_StoreMemberTabs> createState() => _StoreMemberTabsState();
}

class _StoreMemberTabsState extends State<_StoreMemberTabs> {
  bool _member = true;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 35,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab('Member', true),
        _tab('Non-Member', false),
      ]),
    );
  }

  Widget _tab(String label, bool selected) {
    final active = _member == selected;
    return InkWell(
      onTap: () => setState(() => _member = selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 35,
        alignment: Alignment.center,
        constraints: const BoxConstraints(minWidth: 130),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          // Metallic green gradient with squared bottom edges, not a pill.
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF459D82),
                    Color(0xFF176B52),
                    Color(0xFF0F483B)
                  ],
                )
              : null,
          color: active ? null : const Color(0xFFE2E8E4),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(selected ? 16 : 0),
            topRight: Radius.circular(selected ? 0 : 16),
          ),
        ),
        child: Text(label,
            maxLines: 1,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : storeForest)),
      ),
    );
  }
}

/// Infinite scrolling brand tagline. It does not rebuild the page content.
class _StoreSloganTicker extends StatefulWidget {
  const _StoreSloganTicker();

  @override
  State<_StoreSloganTicker> createState() => _StoreSloganTickerState();
}

class _StoreSloganTickerState extends State<_StoreSloganTicker>
    with SingleTickerProviderStateMixin {
  static const _message =
      '🇸🇬  Discover Mandai WildLife: Where the Ordinary Becomes Extraordinary';
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 23),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
        return const SizedBox.shrink();
      }
      final painter = TextPainter(
        text: TextSpan(text: _message, style: style),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final textWidth = painter.width + 4;
      final viewWidth = constraints.maxWidth;
      if (reduceMotion) {
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_message,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: style),
          ),
        );
      }
      // Exactly one message crosses the entire ticker viewport.
      // The next cycle begins after the last character exits on the left.
      return ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final x = viewWidth - _controller.value * (viewWidth + textWidth);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: x,
                  top: 0,
                  bottom: 0,
                  width: textWidth,
                  child: Center(
                    child: Text(_message,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: style),
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }
}

/// Header-only preferences. Does not convert checkout prices or change app locale.
/// These UI selections are deliberately isolated from commerce calculations.
class _StoreHeaderPreferences extends StatefulWidget {
  const _StoreHeaderPreferences();

  @override
  State<_StoreHeaderPreferences> createState() =>
      _StoreHeaderPreferencesState();
}

class _StoreHeaderPreferencesState extends State<_StoreHeaderPreferences> {
  String _currency = 'SGD';
  String _language = 'EN';

  static const _currencies = <String, String>{
    'SGD': '🇸🇬',
    'USD': '🇺🇸',
    'IDR': '🇮🇩',
    'MYR': '🇲🇾',
    'EUR': '🇪🇺',
    'GBP': '🇬🇧',
    'JPY': '🇯🇵',
    'CNY': '🇨🇳',
    'AUD': '🇦🇺',
    'INR': '🇮🇳',
  };
  static const _languages = <String, String>{
    'EN': '🇬🇧',
    'ID': '🇮🇩',
    'ZH': '🇨🇳',
    'MS': '🇲🇾',
    'JA': '🇯🇵',
    'KO': '🇰🇷',
    'TH': '🇹🇭',
    'FR': '🇫🇷',
    'DE': '🇩🇪',
    'ES': '🇪🇸',
  };

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 920;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _menu(_currencies, _currency, 'Currency',
          (value) => setState(() => _currency = value), compact),
      const SizedBox(width: 4),
      _menu(_languages, _language, 'Language',
          (value) => setState(() => _language = value), compact),
    ]);
  }

  Widget _menu(Map<String, String> options, String selected, String tooltip,
      ValueChanged<String> change, bool compact) {
    return PopupMenuButton<String>(
      tooltip: '$tooltip (display preference only)',
      onSelected: change,
      itemBuilder: (context) => options.entries
          .map((entry) => PopupMenuItem<String>(
              value: entry.key, child: Text('${entry.value}  ${entry.key}')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(options[selected]!, style: const TextStyle(fontSize: 13)),
          if (!compact) ...[
            const SizedBox(width: 3),
            Text(selected,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
          const Icon(Icons.arrow_drop_down, size: 17, color: Colors.white),
        ]),
      ),
    );
  }
}

/// Presentation-only carousel. All promotional copy and controls are Flutter widgets,
/// never baked into photographs; every slide remains legible at desktop widths.
class StoreWildlifeCarousel extends StatefulWidget {
  const StoreWildlifeCarousel({super.key});

  @override
  State<StoreWildlifeCarousel> createState() => _StoreWildlifeCarouselState();
}

class _StoreWildlifeCarouselState extends State<StoreWildlifeCarousel> {
  static const _slides = [
    (
      image: 'assets/banner/wildlife_01.jpg',
      title: 'Discover wildlife wonders',
      subtitle: 'Explore nature-inspired gifts and keepsakes.'
    ),
    (
      image: 'assets/banner/wildlife_02.jpg',
      title: 'Meet the giant panda',
      subtitle: 'Bring home a little wildlife inspiration.'
    ),
    (
      image: 'assets/banner/wildlife_03.jpg',
      title: 'Celebrate conservation',
      subtitle: 'Thoughtful gifts inspired by the natural world.'
    ),
  ];

  final PageController _pageController = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      _move((_index + 1) % _slides.length);
    });
  }

  void _move(int to) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(to,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final phone = constraints.maxWidth < 390;
          final height = phone
              ? 200.0
              : compact
                  ? 230.0
                  : (constraints.maxWidth / 3.35)
                      .clamp(240.0, 375.0)
                      .toDouble();
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                height: height,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(children: [
                      Positioned.fill(
                          child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (value) =>
                            setState(() => _index = value),
                        itemBuilder: (context, i) {
                          final slide = _slides[i];
                          return Stack(children: [
                            Positioned.fill(
                                child: Image.asset(slide.image,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(color: storeForest))),
                            Positioned.fill(
                                child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        phone
                                            ? 32
                                            : compact
                                                ? 42
                                                : 76,
                                        12,
                                        phone
                                            ? 30
                                            : compact
                                                ? 40
                                                : 70,
                                        12),
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                                maxWidth: phone
                                                    ? 190
                                                    : compact
                                                        ? 240
                                                        : 470),
                                            child: DecoratedBox(
                                                // Limit the translucent shade to the text bounds.
                                                // All pixels above, below and outside this box
                                                // display the photograph without a Flutter scrim.
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  gradient:
                                                      const RadialGradient(
                                                    center:
                                                        Alignment.centerLeft,
                                                    radius: 1.08,
                                                    colors: [
                                                      Color(
                                                          0x3810342A), // Subtle 22% green behind the copy only.
                                                      Color(0x1610342A),
                                                      Color(0x0010342A),
                                                    ],
                                                    stops: [0.0, 0.56, 1.0],
                                                  ),
                                                ),
                                                child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: phone
                                                                ? 6
                                                                : compact
                                                                    ? 12
                                                                    : 20,
                                                            vertical: phone
                                                                ? 6
                                                                : compact
                                                                    ? 12
                                                                    : 18),
                                                    child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(slide.title,
                                                              maxLines: 3,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize:
                                                                      phone
                                                                          ? 18
                                                                          : compact
                                                                              ? 23
                                                                              : 35,
                                                                  height: 1.12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  shadows: const [
                                                                    Shadow(
                                                                        color: Color(
                                                                            0xDF063D2E),
                                                                        blurRadius:
                                                                            12,
                                                                        offset: Offset(
                                                                            0,
                                                                            2)),
                                                                    Shadow(
                                                                        color: Color(
                                                                            0xC70A4D36),
                                                                        blurRadius:
                                                                            6,
                                                                        offset: Offset(
                                                                            1,
                                                                            1)),
                                                                    Shadow(
                                                                        color: Color(
                                                                            0xAF062E25),
                                                                        blurRadius:
                                                                            3,
                                                                        offset: Offset(
                                                                            -1,
                                                                            -1)),
                                                                  ])),
                                                          SizedBox(
                                                              height: phone
                                                                  ? 4
                                                                  : 12),
                                                          Text(slide.subtitle,
                                                              maxLines: compact
                                                                  ? 3
                                                                  : 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                  color: const Color(
                                                                      0xFFF1FFF6),
                                                                  fontSize: phone
                                                                      ? 11
                                                                      : compact
                                                                          ? 12
                                                                          : 17,
                                                                  shadows: const [
                                                                    Shadow(
                                                                        color: Color(
                                                                            0xEF06382B),
                                                                        blurRadius:
                                                                            9,
                                                                        offset: Offset(
                                                                            0,
                                                                            1)),
                                                                    Shadow(
                                                                        color: Color(
                                                                            0xC7104B34),
                                                                        blurRadius:
                                                                            4,
                                                                        offset: Offset(
                                                                            1,
                                                                            1)),
                                                                  ])),
                                                        ]))))))),
                          ]);
                        },
                      )),
                      Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: IconButton.filledTonal(
                                  tooltip: 'Previous banner',
                                  onPressed: () => _move(
                                      (_index + _slides.length - 1) %
                                          _slides.length),
                                  icon: const Icon(Icons.chevron_left)))),
                      Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                              child: IconButton.filledTonal(
                                  tooltip: 'Next banner',
                                  onPressed: () =>
                                      _move((_index + 1) % _slides.length),
                                  icon: const Icon(Icons.chevron_right)))),
                    ]))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _slides.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Semantics(
                      label: 'Show banner ${i + 1}',
                      button: true,
                      child: InkWell(
                          onTap: () => _move(i),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                              width: i == _index ? 22 : 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: i == _index
                                      ? storeGreen
                                      : const Color(0xFFB6CFC3),
                                  borderRadius: BorderRadius.circular(5))))),
                ),
            ]),
          ]);
        },
      );
}
