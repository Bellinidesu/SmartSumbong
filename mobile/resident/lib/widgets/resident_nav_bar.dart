// SmartSumbong — resident bottom navigation.
//
// Figma node 2715:590. Shared by Home, Emergency, Reports, Map and
// Settings, so it lives on its own rather than being copied into five
// screens that would then drift apart.
//
// Uses Material icons rather than the design's exported SVGs. The
// shapes are conventional — house, warning triangle, document, pin,
// person — and shipping five SVG assets to match a stroke weight is not
// worth the maintenance. Worth mentioning to Rose so it is a decision
// rather than a discrepancy she notices later.

import 'package:flutter/material.dart';

import '../theme.dart';

enum ResidentTab {
  home('/home', Icons.home_rounded, 'Home'),
  emergency('/emergency', Icons.warning_amber_rounded, 'Emergency'),
  reports('/reports', Icons.description_outlined, 'Reports'),
  map('/map', Icons.place_outlined, 'Map'),
  settings('/settings', Icons.person_outline_rounded, 'Settings');

  const ResidentTab(this.route, this.icon, this.label);

  final String route;
  final IconData icon;
  final String label;
}

class ResidentNavBar extends StatelessWidget {
  const ResidentNavBar({super.key, required this.current});

  final ResidentTab current;

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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
