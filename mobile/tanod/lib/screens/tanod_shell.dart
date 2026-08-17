// SmartSumbong — tanod shell.
//
// Two tabs, because a tanod does two things: work the queue and say
// whether they are available to. The duty screen is not buried in
// settings — going off duty at the end of a shift is the single most
// consequential thing a tanod does in this app, since a tanod who
// forgets stays in the dispatch queue all night and complaints route to
// someone who is asleep.

import 'package:flutter/material.dart';

import '../theme.dart';
import 'duty_screen.dart';
import 'tickets_screen.dart';

class TanodShell extends StatefulWidget {
  const TanodShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<TanodShell> createState() => _TanodShellState();
}

class _TanodShellState extends State<TanodShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          TicketsScreen(),
          DutyScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Tokens.navy,
        indicatorColor: Tokens.orange,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined, color: Tokens.bg),
            selectedIcon: Icon(Icons.assignment, color: Tokens.navy),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined, color: Tokens.bg),
            selectedIcon: Icon(Icons.badge, color: Tokens.navy),
            label: 'Duty',
          ),
        ],
      ),
    );
  }
}
