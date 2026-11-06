import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'parts/store_header_widgets.dart';
part 'parts/store_discovery_widgets.dart';
part 'parts/store_product_widgets.dart';
part 'parts/store_common_widgets.dart';

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
