import 'package:flutter/material.dart';
import '../../core/themes.dart';

/// Breakpoints for responsive layout design.
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

/// ResponsiveWrapper — wraps the app child with responsive constraints.
/// Used in [MaterialApp.builder] to provide consistent responsive behavior.
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;

  const ResponsiveWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Prevent font scaling in emergency context
            textScaler: TextScaler.noScaling,
          ),
          child: child,
        );
      },
    );
  }
}

/// Responsive layout widget that adapts to screen size.
/// Shows different layouts for mobile, tablet, and desktop.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < Breakpoints.mobile;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.mobile &&
      MediaQuery.of(context).size.width < Breakpoints.desktop;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Breakpoints.desktop && desktop != null) {
          return desktop!;
        }
        if (constraints.maxWidth >= Breakpoints.mobile && tablet != null) {
          return tablet!;
        }
        return mobile;
      },
    );
  }
}

/// Adaptive padding that scales with screen size.
class AdaptivePadding extends StatelessWidget {
  final Widget child;

  const AdaptivePadding({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontal = width >= Breakpoints.desktop
        ? 48.0
        : width >= Breakpoints.mobile
            ? 32.0
            : 16.0;
    final vertical = width >= Breakpoints.desktop
        ? 32.0
        : width >= Breakpoints.mobile
            ? 24.0
            : 16.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: vertical,
      ),
      child: child,
    );
  }
}

/// Responsive grid that adapts column count to screen width.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= Breakpoints.desktop
        ? 4
        : width >= Breakpoints.mobile
            ? 3
            : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: runSpacing,
        childAspectRatio: 1.0,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// Responsive SOS button size based on screen width.
class ResponsiveSosButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isSending;
  final int countdown;

  const ResponsiveSosButton({
    super.key,
    this.onTap,
    this.isSending = false,
    this.countdown = 5,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final size = width >= Breakpoints.desktop
        ? 280.0
        : width >= Breakpoints.mobile
            ? 240.0
            : 200.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFFFF5252),
            Color(0xFFD32F2F),
            Color(0xFFB71C1C),
          ],
          stops: [0.3, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: isSending
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 4,
                    ),
                  )
                : countdown < 5
                    ? Text(
                        '$countdown',
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 64,
                            color: Colors.white,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

