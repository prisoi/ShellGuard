import 'package:flutter/material.dart';

class SortHeaderCell extends StatelessWidget {
  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final int flex;

  const SortHeaderCell({
    super.key,
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active
                      ? const Color(0xFF2563eb)
                      : const Color(0xFF6b7c93),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              active
                  ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 14,
              color: active
                  ? const Color(0xFF2563eb)
                  : const Color(0xFF9ca3af),
            ),
          ],
        ),
      ),
    );
  }
}
