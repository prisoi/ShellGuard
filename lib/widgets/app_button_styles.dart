import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1d4ed8);
  static const Color primaryHover = Color(0xFF1e40af);
  static const Color primarySoft = Color(0xFFeff6ff);
  static const Color success = Color(0xFF059669);
  static const Color successSoft = Color(0xFFecfdf5);
  static const Color warning = Color(0xFFd97706);
  static const Color warningSoft = Color(0xFFfffbeb);
  static const Color danger = Color(0xFFdc2626);
  static const Color dangerSoft = Color(0xFFfef2f2);
  static const Color textPrimary = Color(0xFF1a2332);
  static const Color textMuted = Color(0xFF64748b);
  static const Color border = Color(0xFFdce3eb);
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color disabledBackground = Color(0xFFE2E8F0);
  static const Color disabledForeground = Color(0xFF94A3B8);
}

class AppButtonStyles {
  static const double controlHeight = 40;
  static const EdgeInsetsGeometry _defaultPadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 10,
  );
  static const double _defaultRadius = 8;

  static ButtonStyle primary({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.disabledBackground,
      disabledForegroundColor: AppColors.disabledForeground,
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle success({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.disabledBackground,
      disabledForegroundColor: AppColors.disabledForeground,
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle warning({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: AppColors.warning,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.disabledBackground,
      disabledForegroundColor: AppColors.disabledForeground,
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle secondary({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primary,
      disabledBackgroundColor: Colors.white,
      disabledForegroundColor: AppColors.disabledForeground,
      side: const BorderSide(color: AppColors.primary),
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle subtle({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: AppColors.surfaceMuted,
      foregroundColor: AppColors.textMuted,
      disabledBackgroundColor: AppColors.disabledBackground,
      disabledForegroundColor: AppColors.disabledForeground,
      side: const BorderSide(color: AppColors.border),
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle danger({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: AppColors.dangerSoft,
      foregroundColor: AppColors.danger,
      disabledBackgroundColor: AppColors.disabledBackground,
      disabledForegroundColor: AppColors.disabledForeground,
      side: const BorderSide(color: Color(0xFFFECACA)),
      padding: padding ?? _defaultPadding,
      minimumSize: const Size(0, controlHeight),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle text({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      disabledForegroundColor: AppColors.disabledForeground,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle textDanger({
    EdgeInsetsGeometry? padding,
    double radius = _defaultRadius,
  }) {
    return TextButton.styleFrom(
      foregroundColor: AppColors.danger,
      disabledForegroundColor: AppColors.disabledForeground,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class AppIconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color backgroundColor;
  final double iconSize;

  const AppIconActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.foregroundColor = AppColors.textMuted,
    this.backgroundColor = Colors.transparent,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: AppColors.disabledBackground,
        disabledForegroundColor: AppColors.disabledForeground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return foregroundColor.withValues(alpha: 0.18);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return foregroundColor.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
      icon: Icon(icon, size: iconSize),
    );
  }
}

class AppFieldStyles {
  static BoxDecoration toolbarDecoration({
    Color backgroundColor = Colors.white,
    Color borderColor = AppColors.border,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borderColor),
    );
  }

  static InputDecoration toolbarInput({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      isDense: true,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    );
  }

  static InputDecoration outlined({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    );
  }
}

class AppControlShell extends StatelessWidget {
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;

  const AppControlShell({
    super.key,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.backgroundColor = Colors.white,
    this.borderColor = AppColors.border,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: AppButtonStyles.controlHeight,
      child: Container(
        padding: padding,
        decoration: AppFieldStyles.toolbarDecoration(
          backgroundColor: backgroundColor,
          borderColor: borderColor,
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

class AppProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color color;
  final Color backgroundColor;
  final double radius;

  const AppProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
    this.backgroundColor = const Color(0xFFF0F4F8),
    this.radius = 3,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: safeValue,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      ),
    );
  }
}
