import 'package:flutter/material.dart';
import '../../theme/app_dimensions.dart';
import '../theme/app_colors.dart';

enum CardVariant {
  basic,
  elevated,
  outlined,
  filled,
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = CardVariant.basic,
    this.padding,
    this.margin,
    this.onTap,
    this.width,
    this.height,
    this.color,
  });

  const AppCard.basic({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.width,
    this.height,
    this.color,
  }) : variant = CardVariant.basic;

  const AppCard.elevated({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.width,
    this.height,
    this.color,
  }) : variant = CardVariant.elevated;

  const AppCard.outlined({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.width,
    this.height,
    this.color,
  }) : variant = CardVariant.outlined;

  final Widget child;
  final CardVariant variant;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final Color? color;

  @override
  Widget build(BuildContext context) {

    final cardContent = padding != null 
        ? Padding(padding: padding!, child: child)
        : child;

    final card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: _getDecoration(),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              child: cardContent,
            )
          : cardContent,
    );

    return card;
  }

  BoxDecoration _getDecoration() {
    switch (variant) {
      case CardVariant.basic:
        return BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          border: Border.all(color: AppColors.borderLight, width: 1),
        );

      case CardVariant.elevated:
        return BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppColors.overlay.withOpacity(0.04),
              blurRadius: 6,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        );

      case CardVariant.outlined:
        return BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          border: Border.all(color: AppColors.accent.withOpacity(0.2), width: 1.5),
        );

      case CardVariant.filled:
        return BoxDecoration(
          color: AppColors.backgroundTertiary,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          border: Border.all(color: AppColors.borderLight, width: 1),
        );
    }
  }
}
