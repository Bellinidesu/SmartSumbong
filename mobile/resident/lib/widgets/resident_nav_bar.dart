// SmartSumbong — resident bottom navigation.
//
// Figma "Footer" (2715:590, the same group on every resident frame).
// Shared by Home, Emergency, Reports, Map and Settings, so it lives on its
// own rather than being copied into five screens that would then drift
// apart.
//
// 1:1 with the frame (23 Sep 2026): the design's own five icons, exported
// from Figma and tinted from the theme so dark mode still reads, instead
// of the Material look-alikes this used before; 14px labels, 700 for the
// active tab and 500 otherwise, all #F3F3F3; a 50x2 line 6 from the top
// marks the active tab. Positions come from the frame: tabs spread edge
// to edge with 37 padding, and each icon and label keeps its own offset
// from the bar's top edge.

import 'package:flutter/material.dart';

import '../theme.dart';

enum ResidentTab {
  // route, label, icon asset, icon size, icon top and label top (both
  // measured from the bar's top edge in the frame).
  home('/home', 'Home', 'nav-home', 24, 24, 19, 43),
  emergency('/emergency', 'Emergency', 'nav-emergency', 26, 26, 17, 43),
  reports('/reports', 'Reports', 'nav-reports', 21, 20, 19, 44),
  map('/map', 'Map', 'nav-map', 22, 19, 17, 44),
  settings('/settings', 'Settings', 'nav-settings', 16, 23, 16, 45);

  const ResidentTab(this.route, this.label, this.asset, this.iconWidth,
      this.iconHeight, this.iconTop, this.labelTop);

  final String route;
  final String label;
  final String asset;
  final double iconWidth;
  final double iconHeight;
  final double iconTop;
  final double labelTop;
}

class ResidentNavBar extends StatelessWidget {
  const ResidentNavBar({super.key, required this.current});

  final ResidentTab current;

  /// The frame's 37 side padding, less each tab's [_NavItem.tapSlop], so
  /// the tabs' visible content still starts and ends 37 from the edges.
  static const _sidePadding = 37.0 - _NavItem.tapSlop;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tab in ResidentTab.values)
                  _NavItem(
                    tab: tab,
                    active: tab == current,
                    onTap: () {
                      if (tab == current) return;
                      // Replace rather than push: the tabs are peers, and
                      // stacking them would build a back stack five deep
                      // from tapping around.
                      Navigator.of(context).pushReplacementNamed(tab.route);
                    },
                  ),
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

  /// Extra tappable width on each side of a tab. The drawn tabs are as
  /// narrow as the frame's (Home is 35 wide); this keeps the touch target
  /// finger-sized without moving anything that is drawn.
  static const tapSlop = 12.0;

  @override
  Widget build(BuildContext context) {
    final colour = context.colors.bg;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: tapSlop),
        child: SizedBox(
          height: 77,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 6),
              // Takes no width, so the 50-wide marker cannot widen a
              // 35-wide tab and shift the others.
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
                tab.label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
