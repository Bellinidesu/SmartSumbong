// SmartSumbong — resident bottom navigation (branch B).
//
// Home at the far left, Emergency, the Report button in the middle,
// Reports, Settings at the far right. The Report button starts a new
// report (/submit-report) rather than switching tabs — filing is what
// the app is for, so it sits where the thumb rests. Map left the bar to
// make room; it is still one tap away on Home's "View map" card, and the
// Map screen shows the bar with no tab marked.
//
// The bar keeps the Figma footer's look: the design's own icons tinted
// from the theme, 14px labels, 700 for the active tab and 500 otherwise,
// and a 50x2 line 6 from the top over the active tab.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

enum ResidentTab {
  // route, icon asset, icon size, icon top and label top (both measured
  // from the bar's top edge in the frame).
  home('/home', 'nav-home', 24, 24, 19, 43),
  emergency('/emergency', 'nav-emergency', 26, 26, 17, 43),
  reports('/reports', 'nav-reports', 21, 20, 19, 44),

  /// Off the bar on branch B; kept so the Map screen can say where it is.
  map('/map', 'nav-map', 22, 19, 17, 44),
  settings('/settings', 'nav-settings', 16, 23, 16, 45);

  const ResidentTab(this.route, this.asset, this.iconWidth, this.iconHeight,
      this.iconTop, this.labelTop);

  final String route;
  final String asset;
  final double iconWidth;
  final double iconHeight;
  final double iconTop;
  final double labelTop;

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

  final ResidentTab current;

  static const _fontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    Widget tab(ResidentTab t) => Expanded(
          child: _NavItem(
            tab: t,
            active: t == current,
            onTap: () {
              if (t == current) return;
              // Replace rather than push: the tabs are peers, and
              // stacking them would build a back stack from tapping
              // around.
              Navigator.of(context).pushReplacementNamed(t.route);
            },
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: context.colors.navy,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          // 917 (frame bottom) - 840 (bar top).
          height: 77,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tab(ResidentTab.home),
                tab(ResidentTab.emergency),
                const Expanded(child: _ReportButton()),
                tab(ResidentTab.reports),
                tab(ResidentTab.settings),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final ResidentTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = context.colors.bg;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label(context.s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ExcludeSemantics(
          child: Column(
            children: [
              const SizedBox(height: 6),
              // Takes no width, so the 50-wide marker cannot widen a tab.
              SizedBox(
                width: 0,
                height: 2,
                child: OverflowBox(
                  minWidth: 50,
                  maxWidth: 50,
                  child: active ? ColoredBox(color: colour) : null,
                ),
              ),
              SizedBox(height: tab.iconTop - 8),
              Image.asset(
                'assets/images/${tab.asset}.png',
                width: tab.iconWidth,
                height: tab.iconHeight,
                color: colour,
              ),
              SizedBox(height: tab.labelTop - tab.iconTop - tab.iconHeight),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tab.label(context.s),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: ResidentNavBar._fontSize,
                    height: 20 / 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The middle of the bar: a 40 orange circle with a 2px page-colour ring
/// and a plus, "Report" under it on the other labels' line (43 from the
/// bar's top). Opens the report form.
class _ReportButton extends StatelessWidget {
  const _ReportButton();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;
    return Semantics(
      button: true,
      label: s.navReport,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/submit-report'),
        borderRadius: BorderRadius.circular(16),
        child: ExcludeSemantics(
          child: Column(
            children: [
              const SizedBox(height: 2),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 26, color: Colors.white),
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  s.navReport,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 13,
                    height: 20 / 14,
                    fontWeight: FontWeight.w700,
                    color: c.bg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
