import 'package:flutter/material.dart';

enum LeuLogoVariant { full, iconOnly, white }

class LeuLogo extends StatelessWidget {
  const LeuLogo({
    super.key,
    this.size = 120,
    this.variant = LeuLogoVariant.full,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.withShadow = false,
  });

  final double size;
  final LeuLogoVariant variant;
  final BoxFit fit;
  final Alignment alignment;
  final bool withShadow;

  String get _asset => switch (variant) {
        LeuLogoVariant.full => 'assets/images/logo-color.png',
        LeuLogoVariant.iconOnly => 'assets/images/logo-without-text.png',
        LeuLogoVariant.white => 'assets/images/logo-blue.jpg',
      };

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      _asset,
      width: variant == LeuLogoVariant.iconOnly ? size : size,
      height: variant == LeuLogoVariant.iconOnly ? size : null,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: variant == LeuLogoVariant.iconOnly ? size : size * 0.38,
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      ),
    );

    if (!withShadow) return image;

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: image,
    );
  }
}
