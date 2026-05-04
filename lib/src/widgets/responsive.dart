import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 720;
  static const double tablet = 1120;
  static const double desktop = 1440;
}

bool isMobileWidth(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.mobile;
bool isTabletWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.mobile && MediaQuery.sizeOf(context).width < Breakpoints.tablet;
bool isDesktopWidth(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

int adaptiveColumns(BuildContext context, {int mobile = 1, int tablet = 2, int desktop = 3}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= Breakpoints.tablet) return desktop;
  if (width >= Breakpoints.mobile) return tablet;
  return mobile;
}

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1440,
    this.horizontalPadding = 0,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }
}
