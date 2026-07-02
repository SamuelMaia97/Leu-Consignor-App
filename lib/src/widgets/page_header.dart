import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'responsive.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.actions = const [],
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? description;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = isMobileWidth(context) ||
            (trailing != null && constraints.maxWidth < 1180);

        final trailingWidget = trailing == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: trailing!,
              );

        final headerContent = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderText(
                    eyebrow: eyebrow,
                    title: title,
                    description: description,
                  ),
                  if (trailingWidget != null) ...[
                    const SizedBox(height: 18),
                    trailingWidget,
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _ActionWrap(actions: actions),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderText(
                          eyebrow: eyebrow,
                          title: title,
                          description: description,
                        ),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _ActionWrap(actions: actions),
                        ],
                      ],
                    ),
                  ),
                  if (trailingWidget != null) ...[
                    const SizedBox(width: 24),
                    trailingWidget,
                  ],
                ],
              );

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(compact ? 22 : 30),
          decoration: BoxDecoration(
            gradient: palette.heroGradient,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: palette.brand.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -58,
                top: -74,
                child: _HeaderOrb(
                  size: 210,
                  color: Colors.white.withValues(alpha: 0.075),
                ),
              ),
              Positioned(
                right: 42,
                bottom: -120,
                child: _HeaderOrb(
                  size: 190,
                  color: Colors.white.withValues(alpha: 0.052),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(
                      offset: Offset(compact ? 32 : 46, 0),
                      child: Opacity(
                        opacity: compact ? 0.16 : 0.18,
                        child: Image.asset(
                          'assets/images/logo-without-text.png',
                          width: compact ? 150 : 220,
                          height: compact ? 150 : 220,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              headerContent,
            ],
          ),
        );
      },
    );
  }
}

class _HeaderOrb extends StatelessWidget {
  const _HeaderOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _ActionWrap extends StatelessWidget {
  const _ActionWrap({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final baseTheme = Theme.of(context);
    final elevatedStyle =
        baseTheme.elevatedButtonTheme.style ?? const ButtonStyle();
    final outlinedStyle =
        baseTheme.outlinedButtonTheme.style ?? const ButtonStyle();

    return Theme(
      data: baseTheme.copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: elevatedStyle.copyWith(
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: 0.12);
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: 0.48);
              }
              return palette.brandStrong;
            }),
            iconColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: 0.48);
              }
              return palette.brandStrong;
            }),
            overlayColor: WidgetStatePropertyAll(
              palette.brandSoft.withValues(alpha: 0.55),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: outlinedStyle.copyWith(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: 0.48);
              }
              return Colors.white;
            }),
            iconColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: 0.48);
              }
              return Colors.white;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              final alpha = states.contains(WidgetState.disabled) ? 0.24 : 0.9;
              return BorderSide(color: Colors.white.withValues(alpha: alpha));
            }),
            overlayColor: WidgetStatePropertyAll(
              Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: actions,
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final descriptionText = description?.trim();
    final eyebrowText = eyebrow.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrowText.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              eyebrowText.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFDCE6F3),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.55,
              ),
        ),
        if (descriptionText != null && descriptionText.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              descriptionText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFEAF0F7),
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
