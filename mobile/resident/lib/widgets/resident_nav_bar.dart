// SmartSumbong — resident bottom bar (branch D).
//
// The Figma footer as the C app has it: filled with the role colour
// (barangay navy by day, pale at night), the design's own icons and the
// labels in the page colour, 30px top corners, a 2px line over the tab
// you are on. Five equal tabs; the tabs are peers, so a tap replaces the
// screen rather than stacking it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../d/d_theme.dart';
import '../i18n.dart';

enum ResidentTab {
  home('/home', 'nav-home', 24, 24),
  emergency('/emergency', 'nav-emergency', 26, 26),
  reports('/reports', 'nav-reports', 22, 21),
  map('/map', 'nav-map', 23, 20),
  settings('/settings', 'nav-settings', 17, 24);

  const ResidentTab(this.route, this.asset, this.iconWidth, this.iconHeight);

  final String route;
  final String asset;
  final double iconWidth;
  final double iconHeight;

  String label(Strings s) => switch (this) {
        home => s.navHome,
        emergency => s.navEmergency,
        reports => s.navReports,
        map => s.navMap,
        settings => s.navSettings,
      };
}

class ResidentNavBar extends StatelessWidget {
  const ResidentNavBar({super.key, required this.current});

  /// Null on a screen reached from the bar but not one of its tabs.
  final ResidentTab? current;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    return DBar(
      colors: d,
      children: [
        for (final t in ResidentTab.values)
          DBarTab(
            label: t.label(s),
            icon: Image.asset('assets/images/${t.asset}.png', width: t.iconWidth, height: t.iconHeight, color: d.barFg),
            active: t == current,
            color: d.barFg,
            onTap: () {
              if (t == current) return;
              Navigator.of(context).pushReplacementNamed(t.route);
            },
          ),
      ],
    );
  }
}

/// The bar itself, shared with the tanod's.
class DBar extends StatelessWidget {
  const DBar({super.key, required this.colors, required this.children});

  final DColors colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // The system buttons sit on this bar: dark ones on a light bar.
    final light = colors.bar.computeLuminance() > .5;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: Theme.of(context).brightness,
      ),
      child: Container(
      decoration: BoxDecoration(
        color: colors.bar,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 77,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in children) Expanded(child: c),
            ]),
          ),
        ),
      ),
    ),
    );
  }
}

class DBarTab extends StatelessWidget {
  const DBarTab({super.key, required this.label, required this.icon, required this.active, required this.color, required this.onTap});

  final String label;
  final Widget icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ExcludeSemantics(
          // B1 (Ace, 7 Oct 2026): a short orange line over the active tab,
          // the others a little quieter.
          child: Opacity(
            // .82, not quieter: inactive labels keep 4.5:1 contrast (WCAG AA).
            opacity: active ? 1 : .82,
            child: Column(children: [
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active ? 26 : 0,
              height: 3,
              decoration: BoxDecoration(color: DColors.orange, borderRadius: BorderRadius.circular(3)),
            ),
            const Spacer(),
            SizedBox(height: 26, child: Center(child: icon)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  // Tab labels stay one size, so five fit evenly at any phone text size.
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: color)),
            ),
            const SizedBox(height: 10),
          ]),
          ),
        ),
      ),
    );
  }
}
