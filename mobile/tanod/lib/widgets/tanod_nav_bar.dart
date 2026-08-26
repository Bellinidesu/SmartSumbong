// SmartSumbong — tanod bottom navigation.
//
// Three tabs, per HOME - TANOD: Home, Reports, Settings. Duty status is
// not among them — it lives on Home as a dropdown, which is why the
// standalone Duty screen the app started with is gone.
//
// Uses Material icons rather than the design's exported SVGs. The
// shapes are conventional — house, warning triangle, document, pin,
// person — and shipping five SVG assets to match a stroke weight is not
// worth the maintenance. Worth mentioning to Rose so it is a decision
// rather than a discrepancy she notices later.

import 'package:flutter/material.dart';

import '../theme.dart';

enum TanodTab {
  home('/home', Icons.home_rounded, 'Home'),
  // A speech bubble with an exclamation, per the frame — the same mark
  // the wordmark uses. Icons.description_outlined (a document) is what
  // the resident bar carries and is the closer miss of the two.
  reports('/reports', Icons.feedback_outlined, 'Reports'),
  settings('/settings', Icons.person_rounded, 'Settings');

  const TanodTab(this.route, this.icon, this.label);

  final String route;
  final IconData icon;
  final String label;
}

class TanodNavBar extends StatelessWidget {
  const TanodNavBar({super.key, required this.current});

  final TanodTab current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Tokens.navy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final tab in TanodTab.values)
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The short rule above the active tab. Present in every
              // frame of both apps and missing from both nav bars.
              Container(
                width: 26,
                height: 3,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: active ? Tokens.bg : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                tab.icon,
                size: 26,
                color: Tokens.bg.withValues(alpha: active ? 1 : 0.75),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: Tokens.bg.withValues(alpha: active ? 1 : 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
