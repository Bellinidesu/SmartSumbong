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

import '../i18n.dart';
import '../theme.dart';

enum ResidentTab {
  // route, icon asset, icon size, icon top and label top (both measured
  // from the bar's top edge in the frame).
  home('/home', 'nav-home', 24, 24, 19, 43),
  emergency('/emergency', 'nav-emergency', 26, 26, 17, 43),
  reports('/reports', 'nav-reports', 21, 20, 19, 44),
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

  static const _framePadding = 37.0; // the frame's side padding
  static const _minPadding = 10.0;
  static const _minGap = 8.0; // least space kept between two tabs
  static const _fontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final scaler = MediaQuery.textScalerOf(context);
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
          child: LayoutBuilder(
            builder: (context, box) {
              final tabs = ResidentTab.values;
              final w = box.maxWidth;

              // Each tab is as wide as its icon or its label, whichever is
              // wider, measured with the phone's own text scaling.
              double labelWidth(ResidentTab t) => (TextPainter(
                    text: TextSpan(
                      text: t.label(s),
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: _fontSize,
                        fontWeight: t == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout())
                      .width;
              final widths = [
                for (final t in tabs)
                  labelWidth(t) > t.iconWidth ? labelWidth(t) : t.iconWidth,
              ];
              final total = widths.fold<double>(0, (a, b) => a + b);
              const gaps = _minGap * 4;

              // As drawn in the frame when it fits. Narrower phones, long
              // Tagalog labels or a large system font size: give up side
              // padding first, then shrink the tabs, rather than overflow.
              var pad = _framePadding;
              var scale = 1.0;
              if (w - 2 * pad - total < gaps) {
                pad = ((w - total - gaps) / 2).clamp(_minPadding, _framePadding);
                if (w - 2 * pad - total < gaps) {
                  scale = (w - 2 * pad - gaps) / total;
                }
              }
              final gap = (w - 2 * pad - total * scale) / (tabs.length - 1);

              final lefts = <double>[];
              var x = pad;
              for (final tw in widths) {
                lefts.add(x);
                x += tw * scale + gap;
              }
              final centres = [
                for (var i = 0; i < tabs.length; i++)
                  lefts[i] + widths[i] * scale / 2,
              ];

              return Stack(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Positioned(
                      left: lefts[i],
                      top: 0,
                      width: widths[i] * scale,
                      height: 77,
                      child: _NavItem(
                        tab: tabs[i],
                        active: tabs[i] == current,
                        scale: scale,
                      ),
                    ),
                  // Tap areas run between the midpoints of neighbouring
                  // tabs and the full height of the bar, so every tab is
                  // easy to hit without moving anything that is drawn.
                  for (var i = 0; i < tabs.length; i++)
                    Positioned(
                      left: i == 0 ? 0 : (centres[i - 1] + centres[i]) / 2,
                      right: i == tabs.length - 1
                          ? 0
                          : w - (centres[i] + centres[i + 1]) / 2,
                      top: 0,
                      bottom: 0,
                      child: Semantics(
                        button: true,
                        selected: tabs[i] == current,
                        label: tabs[i].label(s),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            final tab = tabs[i];
                            if (tab == current) return;
                            // Replace rather than push: the tabs are peers,
                            // and stacking them would build a back stack
                            // five deep from tapping around.
                            Navigator.of(context)
                                .pushReplacementNamed(tab.route);
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
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
    required this.scale,
  });

  final ResidentTab tab;
  final bool active;

  /// Below 1 only when the bar would otherwise overflow; see above.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colour = context.colors.bg;
    return ExcludeSemantics(
      // The tap area above carries the label for screen readers.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 6),
          // Takes no width, so the 50-wide marker cannot widen a narrow
          // tab.
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
            width: tab.iconWidth * scale,
            height: tab.iconHeight * scale,
            color: colour,
          ),
          SizedBox(
              height: tab.labelTop - tab.iconTop - tab.iconHeight * scale),
          Text(
            tab.label(context.s),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontSize: ResidentNavBar._fontSize * scale,
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
