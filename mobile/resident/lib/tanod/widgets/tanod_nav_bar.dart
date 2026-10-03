// SmartSumbong — tanod bottom bar (branch D).
//
// The resident's bar in the tanod's ink (pale at night), with the duty
// status raised in the middle: a 60px circle in the status colour, ringed
// in the bar's colour so it reads as cut into the bar, a soft glow of its
// own colour under it. Tapping it opens the status popup, not a tab.

import 'package:flutter/material.dart';

import '../../d/d_theme.dart';
import '../../widgets/resident_nav_bar.dart' show DBar, DBarTab;
import '../duty.dart';
import '../tanod_strings.dart';
import '../widgets/duty_sheet.dart';

enum TanodTab {
  home('/t/home', 'nav-home', null, 24, 24),
  reports('/t/reports', 'nav-reports', null, 22, 21),
  history('/t/history', null, Icons.history_rounded, 26, 26),
  settings('/t/settings', 'nav-settings', null, 17, 24);

  const TanodTab(this.route, this.asset, this.icon, this.iconWidth, this.iconHeight);

  final String route;
  final String? asset;
  final IconData? icon;
  final double iconWidth;
  final double iconHeight;

  String label(TanodStrings s) => switch (this) {
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

  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    Widget tab(TanodTab t) => DBarTab(
          label: t.label(s),
          icon: t.asset != null
              ? Image.asset('assets/images/${t.asset}.png', width: t.iconWidth, height: t.iconHeight, color: d.barFg)
              : Icon(t.icon, size: t.iconHeight, color: d.barFg),
          active: t == current,
          color: d.barFg,
          onTap: () {
            if (t == current) return;
            Navigator.of(context).pushReplacementNamed(t.route);
          },
        );
    return DBar(colors: d, children: [
      tab(TanodTab.home),
      tab(TanodTab.reports),
      _StatusButton(colors: d),
      tab(TanodTab.history),
      tab(TanodTab.settings),
    ]);
  }
}

class _StatusButton extends StatefulWidget {
  const _StatusButton({required this.colors});

  final DColors colors;

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
    final s = context.ts;
    final d = widget.colors;
    return ListenableBuilder(
      listenable: _duty,
      builder: (context, _) {
        final status = _duty.status;
        final label = status == null ? s.navStatus : s.dutyStateLabel(status.wire);
        final c = dutyColour(context, status);
        return Semantics(
          button: true,
          label: '${s.homeStatusQuestion} $label',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDutySheet(context),
            child: ExcludeSemantics(
              child: OverflowBox(
                maxHeight: 77 + 28,
                alignment: Alignment.bottomCenter,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: d.bar, width: 4),
                      boxShadow: [BoxShadow(color: c.withValues(alpha: .5), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.shield_outlined, size: 24, color: Colors.white),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: TextStyle(fontFamily: 'Urbanist', fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w800, color: d.barFg)),
                  ),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
