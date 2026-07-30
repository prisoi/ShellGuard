import 'package:flutter/material.dart';

class AdaptivePageLayout extends StatelessWidget {
  final List<Widget> header;
  final Widget body;
  final List<Widget> footer;
  final double estimatedReservedHeight;
  final double minBodyHeight;
  final EdgeInsets padding;
  final Color backgroundColor;

  const AdaptivePageLayout({
    super.key,
    required this.header,
    required this.body,
    this.footer = const [],
    required this.estimatedReservedHeight,
    this.minBodyHeight = 220,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor = const Color(0xFFf0f4f8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      color: backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyHeight = (constraints.maxHeight - estimatedReservedHeight)
              .clamp(minBodyHeight, double.infinity);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  ...header,
                  SizedBox(height: bodyHeight, child: body),
                  ...footer,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
