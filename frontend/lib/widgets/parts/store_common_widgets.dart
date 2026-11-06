part of '../store_widgets.dart';

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
