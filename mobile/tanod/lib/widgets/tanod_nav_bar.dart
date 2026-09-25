// SmartSumbong — tanod bottom navigation.
//
// Three tabs, per HOME - TANOD: Home, Reports, Settings. Duty status is
// not among them — it lives on Home as a dropdown, which is why the
// standalone Duty screen the app started with is gone.
//
// 1:1 with the frame's "Footer" (25 Sep 2026), as the resident bar is:
// the design's own icons, exported from Figma and tinted from the theme
// (the app's ink, so the bar is ink-black by day and pale at night);
// 14px labels, 700 for the active tab and 500 otherwise; a 50x2 line 6
// from the top marks the active tab. Unlike the resident bar's five tabs
// spread edge to edge, these three sit together in the middle, 36 apart,
// as the frame draws them.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

enum TanodTab {
  // route, icon asset, icon size, icon top and label top (both measured
  // from the bar's top edge in the frame).
  home('/home', 'nav-home', 24, 24, 16, 44),
  reports('/reports', 'nav-reports', 21, 20, 19, 44),
  settings('/settings', 'nav-settings', 16, 23, 16, 45);

  const TanodTab(this.route, this.asset, this.iconWidth, this.iconHeight,
      this.iconTop, this.labelTop);

  final String route;
  final String asset;
  final double iconWidth;
  final double iconHeight;
  final double iconTop;
  final double labelTop;

  String label(Strings s) => switch (this) {
        home => s.navHome,
        reports => s.navReports,
        settings => s.navSettings,
      };
}

class TanodNavBar extends StatelessWidget {
  const TanodNavBar({super.key, required this.current});

  final TanodTab current;

  static const _gap = 36.0; // the frame's space between tabs
  static const _fontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in TanodTab.values) ...[
                if (tab != TanodTab.values.first)
                  const SizedBox(width: _gap),
                Semantics(
                  button: true,
                  selected: tab == current,
                  label: tab.label(s),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (tab == current) return;
                      // Replace rather than push: the tabs are peers, and
                      // stacking them would build a back stack from
                      // tapping around.
                      Navigator.of(context).pushReplacementNamed(tab.route);
                    },
                    // A little wider than drawn so each tab is easy to
                    // hit; the gap between them stays the frame's.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _NavItem(tab: tab, active: tab == current),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.active});

  final TanodTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colour = context.colors.bg;
    return ExcludeSemantics(
      // The InkWell's Semantics carries the label for screen readers.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          Text(
            tab.label(context.s),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontSize: TanodNavBar._fontSize,
              height: 20 / 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
