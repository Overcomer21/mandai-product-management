import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const storeGreen = Color(0xFF146C55);
const storeForest = Color(0xFF174D3C);

/// Reusable page shell: consistent header, optional bottom navigation, dynamic page content.
/// Filters belong to the catalogue content; detail, checkout and login do not show them.
class MainMasterLayout extends StatelessWidget {
  const MainMasterLayout(
      {super.key,
      required this.content,
      required this.signedIn,
      required this.isAdmin,
      required this.userLabel,
      required this.cartCount,
      required this.onCart,
      required this.onSignOut,
      required this.onLogin,
      required this.onSignUp,
      required this.searchController,
      required this.onSearchChanged,
      required this.onSearchClear,
      required this.onSearchSubmitted,
      this.onBack,
      this.bottomNavigationBar,
      this.cartCountListenable});

  final Widget content;
  final bool signedIn, isAdmin;
  final String userLabel;
  final int cartCount;
  final ValueListenable<int>? cartCountListenable;
  final VoidCallback onCart, onSignOut, onLogin, onSignUp;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged, onSearchSubmitted;
  final VoidCallback onSearchClear;
  final VoidCallback? onBack;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(
              MediaQuery.sizeOf(context).width >= 1150 ? 176 : 175),
          child: SafeArea(
              bottom: false,
              child: StoreTopPanel(
                  signedIn: signedIn,
                  isAdmin: isAdmin,
                  userLabel: userLabel,
                  cartCount: cartCount,
                  cartCountListenable: cartCountListenable,
                  onCart: onCart,
                  onSignOut: onSignOut,
                  onLogin: onLogin,
                  onSignUp: onSignUp,
                  searchController: searchController,
                  onSearchChanged: onSearchChanged,
                  onSearchClear: onSearchClear,
                  onSearchSubmitted: onSearchSubmitted,
                  onBack: onBack)),
        ),
        body: content,
        bottomNavigationBar: bottomNavigationBar,
      );
}

/// Reusable two-row header shared by catalogue, detail, login and checkout.
/// Only presentation belongs here; caller retains navigation/search/auth state.
class StoreTopPanel extends StatelessWidget {
  const StoreTopPanel(
      {super.key,
      required this.signedIn,
      required this.isAdmin,
      required this.userLabel,
      required this.onSignOut,
      required this.onCart,
      required this.onLogin,
      required this.onSignUp,
      required this.cartCount,
      required this.searchController,
      required this.onSearchChanged,
      required this.onSearchClear,
      required this.onSearchSubmitted,
      this.onBack,
      this.cartCountListenable});

  final bool signedIn, isAdmin;
  final String userLabel;
  final VoidCallback onSignOut, onCart, onLogin, onSignUp;
  final VoidCallback? onBack;
  final int cartCount;
  final ValueListenable<int>? cartCountListenable;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged, onSearchSubmitted;
  final VoidCallback onSearchClear;

  void _copySocialLink(BuildContext context, String social, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$social link copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 650;
    final veryNarrow = width < 390;
    return Material(
      color: storeForest,
      child: Container(
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Color(0x66FFFFFF), width: 0.8))),
        padding:
            EdgeInsets.symmetric(horizontal: compact ? 10 : 26, vertical: 5),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Marketplace-style tabs sit ABOVE Sign up / Log in in the upper-right.
          // Keep the same 35px allocation: only the tab position changes.
          // Mobile/tablet membership tabs: always visible above the top panel actions.
          // Large desktop keeps the existing tab layout unchanged.
          if (width < 1150)
            const SizedBox(
              height: 35,
              child: Align(
                alignment: Alignment.centerRight,
                child: _StoreMemberTabs(),
              ),
            ),
          if (width >= 1150) ...[
            SizedBox(
              height: 35,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Divider(
                        height: 1, thickness: 1, color: Color(0x55FFFFFF)),
                  ),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: _StoreMemberTabs(),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
              height: 42,
              child: Row(children: [
                if (!compact) ...[
                  const Text('Follow us',
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                  const SizedBox(width: 5),
                  IconButton(
                      tooltip: 'Copy Facebook link',
                      icon: const Text('f',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      onPressed: () => _copySocialLink(context, 'Facebook',
                          'https://www.facebook.com/MandaiWildlifeReserve/'),
                      visualDensity: VisualDensity.compact),
                  IconButton(
                      tooltip: 'Copy Instagram link',
                      icon: const Icon(Icons.camera_alt_outlined,
                          size: 19, color: Colors.white),
                      onPressed: () => _copySocialLink(context, 'Instagram',
                          'https://www.instagram.com/mandaiwildlifereserve/'),
                      visualDensity: VisualDensity.compact),
                ],
                if (!compact) const SizedBox(width: 16),
                Expanded(
                    child: compact
                        ? const SizedBox.shrink()
                        : const _StoreSloganTicker()),
                if (!veryNarrow) ...[
                  const SizedBox(width: 6),
                  const _StoreHeaderPreferences(),
                ],
                if (!compact) const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_none_outlined,
                        size: 21, color: Colors.white),
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: const Text('Notifications'),
                                content: const Text('No new notifications.'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Close')),
                                ]))),
                if (signedIn) ...[
                  if (!veryNarrow)
                    ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: compact ? 110 : 260),
                        child: Text(
                            userLabel.isEmpty
                                ? (isAdmin ? 'Administrator' : 'Customer')
                                : userLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white))),
                  IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout_outlined,
                          size: 20, color: Colors.white),
                      onPressed: onSignOut),
                ] else ...[
                  TextButton(
                      onPressed: onSignUp,
                      child: const Text('Sign up',
                          style: TextStyle(color: Colors.white))),
                  TextButton(
                      onPressed: onLogin,
                      child: const Text('Log in',
                          style: TextStyle(color: Colors.white))),
                ],
              ])),
          const SizedBox(height: 5),
          Expanded(
              child: Row(children: [
            if (onBack != null)
              IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
            const Icon(Icons.forest_rounded, color: Colors.white, size: 28),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text('Mandai Merchandise',
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ],
            SizedBox(
                width: veryNarrow
                    ? 4
                    : compact
                        ? 10
                        : 28),
            Expanded(
                child: SizedBox(
                    height: 49,
                    child: StoreSearchBar(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        onClear: onSearchClear,
                        onSubmitted: onSearchSubmitted))),
            if (signedIn && !isAdmin) ...[
              SizedBox(width: compact ? 2 : 12),
              if (cartCountListenable == null)
                Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    child: IconButton(
                        tooltip: 'Shopping cart',
                        onPressed: onCart,
                        icon: const Icon(Icons.shopping_cart_outlined,
                            color: Colors.white)))
              else
                ValueListenableBuilder<int>(
                  valueListenable: cartCountListenable!,
                  builder: (context, quantity, _) => Badge(
                      isLabelVisible: quantity > 0,
                      label: Text('$quantity'),
                      child: IconButton(
                          tooltip: 'Shopping cart',
                          onPressed: onCart,
                          icon: const Icon(Icons.shopping_cart_outlined,
                              color: Colors.white))),
                ),
            ],
          ])),
          const SizedBox(height: 7),
        ]),
      ),
    );
  }
}

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

/// Reusable search field; search state and query execution remain with the screen.
class StoreSearchBar extends StatelessWidget {
  const StoreSearchBar(
      {super.key,
      required this.controller,
      required this.onChanged,
      required this.onClear,
      this.onSubmitted});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: 'Search wildlife merchandise',
          prefixIcon: IconButton(
            tooltip: 'Search products',
            icon: const Icon(Icons.search),
            onPressed: onSubmitted == null
                ? null
                : () => onSubmitted!(controller.text),
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
      );
}

/// Pure marketing panel. No authentication or navigation logic lives here.
class StoreLoginIntroduction extends StatelessWidget {
  const StoreLoginIntroduction({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.forest, color: storeGreen, size: 70),
            SizedBox(height: 18),
            Text('Mandai Merchandise',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 29,
                    color: storeForest)),
            SizedBox(height: 12),
            Text('Discover wildlife-inspired gifts and souvenirs.',
                style: TextStyle(fontSize: 17, color: Color(0xFF607B6D))),
          ],
        ),
      );
}

/// Reusable informational storefront footer. No new backend dependencies.
/// Links without dedicated pages show explanatory information rather than
/// pretending to perform a transaction or subscribing an email address.
class StoreFooter extends StatelessWidget {
  const StoreFooter(
      {super.key, this.onRunConcurrencyTests, this.onTestingSummary});
  final VoidCallback? onRunConcurrencyTests;
  final VoidCallback? onTestingSummary;

  void _runTests(BuildContext context) {
    Navigator.of(context).pop();
    onRunConcurrencyTests?.call();
  }

  void _showTestingSummary(BuildContext context) {
    Navigator.of(context).pop();
    onTestingSummary?.call();
  }

  void _information(BuildContext context, String title) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(title),
              content: const Text(
                  'Contact the Mandai Merchandise team for assistance. '
                  'This demonstration does not include a dedicated help or subscription service.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'))
              ],
            ));
  }

  Widget _footerLink(BuildContext context, String label) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: () => _information(context, label),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      );

  void _openQuickAccess(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF263F36),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.65,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                  child: Text('Help & Connect',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold))),
              IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
            const SizedBox(height: 12),
            const Text('Need help?',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            ...[
              'How to shop',
              'Help center',
              'Delivery',
              'Returns',
              'Contact us'
            ].map((label) => _footerLink(sheetContext, label)),
            const SizedBox(height: 16),
            const Text('Let’s connect',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            Row(children: [
              IconButton(
                  tooltip: 'Facebook',
                  onPressed: () => _information(sheetContext, 'Facebook'),
                  icon: const Text('f',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold))),
              IconButton(
                  tooltip: 'Instagram',
                  onPressed: () => _information(sheetContext, 'Instagram'),
                  icon: const Icon(Icons.camera_alt_outlined,
                      color: Colors.white)),
            ]),
            if (onTestingSummary != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                  onPressed: () => _showTestingSummary(sheetContext),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Testing checklist & summary'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white)),
            ],
            if (onRunConcurrencyTests != null) ...[
              const SizedBox(height: 18),
              const Text('Developer Tools',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              TextButton.icon(
                  onPressed: () => _runTests(sheetContext),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Run Concurrent Transaction Tests'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white)),
            ],
            const SizedBox(height: 12),
            const Text('About Mandai',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Wildlife-inspired gifts and souvenirs. Every purchase in this app is a demo.',
                style: TextStyle(color: Color(0xFFE2EEE7))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: const Color(0xFF263F36),
            borderRadius: BorderRadius.circular(16)),
        padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 700 ? 14 : 24,
            vertical: MediaQuery.sizeOf(context).width < 700 ? 12 : 26),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          if (narrow) {
            return Row(children: [
              const Expanded(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mandai Merchandise',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('Wildlife-inspired gifts • Demo',
                      style: TextStyle(color: Color(0xFFE2EEE7), fontSize: 10)),
                ],
              )),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openQuickAccess(context),
                icon: const Icon(Icons.menu_open_rounded, size: 17),
                label: const Text('Help & Connect',
                    style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF9CBDAE)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                ),
              ),
            ]);
          }
          final sectionWidth =
              narrow ? constraints.maxWidth : (constraints.maxWidth - 72) / 4;
          Widget section(String heading, Widget child) => SizedBox(
                width: sectionWidth,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(heading,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      child,
                    ]),
              );
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 24, runSpacing: 26, children: [
                  section(
                      'Need help?',
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            'How to shop',
                            'Help center',
                            'Delivery',
                            'Returns',
                            'Contact us'
                          ]
                              .map((label) => _footerLink(context, label))
                              .toList())),
                  section(
                      "Let’s connect",
                      Row(children: [
                        IconButton(
                            tooltip: 'Facebook',
                            onPressed: () => _information(context, 'Facebook'),
                            icon: const Text('f',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 24))),
                        IconButton(
                            tooltip: 'Instagram',
                            onPressed: () => _information(context, 'Instagram'),
                            icon: const Icon(Icons.camera_alt_outlined,
                                color: Colors.white)),
                      ])),
                  if (onTestingSummary != null)
                    section(
                        'Testing',
                        TextButton.icon(
                            onPressed: onTestingSummary,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Testing checklist & summary'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white))),
                  if (onRunConcurrencyTests != null)
                    section(
                        'Developer Tools',
                        TextButton.icon(
                            onPressed: onRunConcurrencyTests,
                            icon: const Icon(Icons.science_outlined),
                            label:
                                const Text('Run Concurrent Transaction Tests'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white))),
                  section(
                      'About Mandai',
                      const Text(
                          'Wildlife-inspired gifts and souvenirs. Every purchase in this app is a demo.',
                          style: TextStyle(
                              color: Color(0xFFE2EEE7), height: 1.5))),
                  section(
                      'Be the first to know',
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'Discover new merchandise and wildlife inspiration.',
                                style: TextStyle(
                                    color: Color(0xFFE2EEE7), height: 1.5)),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _information(context, 'Updates'),
                              icon: const Icon(Icons.mail_outline),
                              label: const Text('Ask about updates'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Color(0xFF9CBDAE))),
                            ),
                          ])),
                ]),
                const SizedBox(height: 24),
                const Divider(color: Color(0xFF799487)),
                const SizedBox(height: 10),
                Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 10,
                    children: [
                      const Text(
                          'Mandai Merchandise • Technical assessment demo',
                          style: TextStyle(
                              color: Color(0xFFE2EEE7), fontSize: 12)),
                      const Text(
                          'No real payments or subscriptions are processed.',
                          style: TextStyle(
                              color: Color(0xFFE2EEE7), fontSize: 12)),
                    ]),
              ]);
        }),
      );
}
