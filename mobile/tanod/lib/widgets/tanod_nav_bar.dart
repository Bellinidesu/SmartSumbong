// SmartSumbong — tanod bottom navigation (branch B).
//
// Five slots: Home at the far left, Reports, the duty status button in
// the middle, History, Settings at the far right. The status button
// wears the current status's colour and opens the status popup
// (widgets/duty_sheet.dart) rather than a tab.
//
// The bar keeps the Figma footer's look: the design's own icons tinted
// from the theme (ink by day, pale at night; History has no Figma icon,
// so it is the Material one in the same box), 14px labels, 700 for the
// active tab and 500 otherwise, and a 50x2 line 6 from the top over the
// active tab.

import 'package:flutter/material.dart';

import '../duty.dart';
import '../i18n.dart';
import '../theme.dart';
import 'duty_sheet.dart';

enum TanodTab {
  // route, icon asset (null: a Material icon), icon size, icon top and
  // label top (both measured from the bar's top edge in the frame).
  home('/home', 'nav-home', null, 24, 24, 16, 44),
  reports('/reports', 'nav-reports', null, 21, 20, 19, 44),
  history('/history', null, Icons.history_rounded, 24, 24, 16, 44),
  settings('/settings', 'nav-settings', null, 16, 23, 16, 45);

  const TanodTab(this.route, this.asset, this.icon, this.iconWidth,
      this.iconHeight, this.iconTop, this.labelTop);

  final String route;
  final String? asset;
  final IconData? icon;
  final double iconWidth;
  final double iconHeight;
  final double iconTop;
  final double labelTop;

  String label(Strings s) => switch (this) {
        home => s.navHome,
        reports => s.navReports,
        history => s.navHistory,
        settings => s.navSettings,
      };
}

class TanodNavBar extends StatelessWidget {
  const TanodNavBar({super.key, required this.current});

  /// Null on a screen reached from the bar but not one of its tabs.
  final TanodTab? current;

  static const _fontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    Widget tab(TanodTab t) => Expanded(
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
                tab(TanodTab.home),
                tab(TanodTab.reports),
                const Expanded(child: _StatusButton()),
                tab(TanodTab.history),
                tab(TanodTab.settings),
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

  final TanodTab tab;
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
              SizedBox(
                width: tab.iconWidth,
                height: tab.iconHeight,
                child: tab.asset != null
                    ? Image.asset('assets/images/${tab.asset}.png',
                        color: colour)
                    : Icon(tab.icon, size: tab.iconHeight, color: colour),
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
                    fontSize: TanodNavBar._fontSize,
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

/// The middle of the bar: a 46 circle in the current status's colour with
/// a 2px page-colour ring, the status under it. Reads the status the
/// first time it is built, so every tab shows it.
class _StatusButton extends StatefulWidget {
  const _StatusButton();

  @override
  State<_StatusButton> createState() => _StatusButtonState();
}

class _StatusButtonState extends State<_StatusButton> {
  final _duty = DutyController.instance;

  @override
  void initState() {
    super.initState();
    if (_duty.status == null) _duty.load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;
    return ListenableBuilder(
      listenable: _duty,
      builder: (context, _) {
        final status = _duty.status;
        final label =
            status == null ? s.navStatus : s.dutyStateLabel(status.wire);
        return Semantics(
          button: true,
          label: '${s.homeStatusQuestion} $label',
          child: InkWell(
            onTap: () => showDutySheet(context),
            borderRadius: BorderRadius.circular(16),
            child: ExcludeSemantics(
              child: Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: dutyColour(context, status),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 2),
                    ),
                    child: const Icon(Icons.badge_outlined,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
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
      },
    );
  }
}
