import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Expanded(
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, color: const Color(0xFF146C55)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(value,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(label, style: const TextStyle(fontSize: 12))
                    ]))
              ]))));
}
