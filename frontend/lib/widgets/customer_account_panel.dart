import 'package:flutter/material.dart';

/// Presentation-only account page. Caller supplies data from the authenticated
/// user/session; no database assumptions, persistence or commerce side effects.
class CustomerAccountPanel extends StatelessWidget {
  const CustomerAccountPanel({
    super.key,
    required this.email,
    required this.onSignOut,
    this.displayName,
    this.deliveryAddress,
    this.phoneNumber,
    this.paymentMethod,
  });

  final String email;
  final String? displayName;
  final String? deliveryAddress;
  final String? phoneNumber;
  final String? paymentMethod;
  final VoidCallback onSignOut;

  String _label(String? value) =>
      value == null || value.trim().isEmpty ? 'Not provided yet' : value.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('My Account',
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF174D3C))),
            const SizedBox(height: 14),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      const CircleAvatar(
                          radius: 27,
                          backgroundColor: Color(0xFFE3F2EA),
                          child: Icon(Icons.person_outline,
                              size: 30, color: Color(0xFF146C55))),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                _label(displayName) == 'Not provided yet'
                                    ? 'Customer'
                                    : _label(displayName),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(email.isEmpty ? 'Email unavailable' : email,
                                overflow: TextOverflow.ellipsis),
                          ])),
                    ]))),
            const SizedBox(height: 10),
            _tile(Icons.local_shipping_outlined, 'Delivery address',
                deliveryAddress),
            _tile(Icons.phone_outlined, 'Phone number', phoneNumber),
            _tile(Icons.credit_card_outlined, 'Payment method', paymentMethod,
                description:
                    'Card details are managed securely by Stripe, not stored in this account.'),
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_outlined),
                label: const Text('Sign out')),
          ]),
        )),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String? value,
          {String? description}) =>
      Card(
          child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Icon(icon, color: const Color(0xFF146C55)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text(_label(value)),
          if (description != null)
            Text(description,
                style: const TextStyle(fontSize: 11, color: Color(0xFF607B6D))),
        ]),
      ));
}
