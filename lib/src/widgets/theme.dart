import 'package:flutter/material.dart';

/// 未指定の色はホストアプリの Theme から解決する。
class GoAlongTheme {
  const GoAlongTheme({
    this.accent,
    this.onAccent,
    this.textColor,
    this.secondaryTextColor,
    this.errorTextColor,
    this.fieldBackground,
    this.fieldBorder,
    this.cardBackground,
    this.titleStyle,
    this.cornerRadius = 12,
  });

  final Color? accent;
  final Color? onAccent;
  final Color? textColor;
  final Color? secondaryTextColor;
  final Color? errorTextColor;
  final Color? fieldBackground;
  final Color? fieldBorder;
  final Color? cardBackground;
  final TextStyle? titleStyle;
  final double cornerRadius;

  GoAlongTheme resolve(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return GoAlongTheme(
      accent: accent ?? colors.onSurface,
      onAccent: onAccent ?? colors.surface,
      textColor: textColor ?? colors.onSurface,
      secondaryTextColor: secondaryTextColor ?? colors.onSurfaceVariant,
      errorTextColor: errorTextColor ?? colors.error,
      fieldBackground: fieldBackground ?? colors.surface,
      fieldBorder: fieldBorder ?? colors.outlineVariant,
      cardBackground: cardBackground ?? colors.surfaceContainerHighest,
      titleStyle: titleStyle ?? theme.textTheme.titleMedium,
      cornerRadius: cornerRadius,
    );
  }
}
