import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.positive = true});
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: positive ? const Color(0xFFE9F6EF) : const Color(0xFFFFF3E6),
          borderRadius: BorderRadius.circular(30)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: positive
                  ? const Color(0xFF13734D)
                  : const Color(0xFFA26823))));
}
