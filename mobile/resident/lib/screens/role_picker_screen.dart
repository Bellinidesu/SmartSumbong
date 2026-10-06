// SmartSumbong — role picker (branch D).
//
// Sits between onboarding and login, and is where "Back to Roles" on the
// login screen returns to. Either card leads to the same login; the
// account's own role decides where it lands afterwards. The tanod card
// tells the login to say "Tanod Profile" and to send Sign Up to tanod
// registration (the admin approves tanod accounts against the roster).
//
// Kim's art in two tall cards — navy for the resident, orange for the
// tanod — each with a soft glow of its own colour and a light halo behind
// the figure. The contour runs the whole screen; the page follows the
// light/dark setting.

import 'package:flutter/material.dart';

import '../d/d_switches.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.dResident;
    return DPage(
      colors: d,
      fullContour: true,
      child: LayoutBuilder(builder: (context, box) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/onboarding-logo.png',
                    width: 250, semanticLabel: 'SmartSumbong', filterQuality: FilterQuality.medium),
                const SizedBox(height: 6),
                Text(s.roleTitle, textAlign: TextAlign.center, style: DType.h1(d.ink).copyWith(fontSize: 28)),
                const SizedBox(height: 22),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _RoleCard(
                      label: s.roleResident,
                      sub: context.tr('Report problems in your area', 'Mag-report ng problema sa inyong lugar'),
                      art: 'assets/images/residenthd.png',
                      gradient: const [Color(0xFF2A62D8), Color(0xFF00308F), Color(0xFF001E5E)],
                      glow: const [Color(0xFF6FA2FF), Color(0xFF1A4FC4)],
                      foreground: Colors.white,
                      dark: d.dark,
                      onTap: () => Navigator.of(context).pushNamed('/login', arguments: 'resident'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _RoleCard(
                      label: s.roleTanod,
                      sub: context.tr('Receive and respond to dispatches', 'Tumanggap at tumugon sa mga dispatch'),
                      art: 'assets/images/tanodhd.png',
                      gradient: const [Color(0xFFFFC062), Color(0xFFFF9800), Color(0xFFE07400)],
                      glow: const [Color(0xFFFFD08A), Color(0xFFFF6A00)],
                      foreground: const Color(0xFF141B34),
                      dark: d.dark,
                      onTap: () => Navigator.of(context).pushNamed('/login', arguments: 'tanod'),
                    ),
                  ),
                ]),
                const SizedBox(height: 26),
                DPrefsRow(colors: d),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.label,
    required this.sub,
    required this.art,
    required this.gradient,
    required this.glow,
    required this.foreground,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final String sub;
  final String art;
  final List<Color> gradient;
  final List<Color> glow;
  final Color foreground;
  final bool dark;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(28);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              // the glow: two soft shadows in the card's own colours
              boxShadow: [
                BoxShadow(color: widget.glow[0].withValues(alpha: widget.dark ? .45 : .35), blurRadius: 30, spreadRadius: -4, offset: const Offset(-4, 12)),
                BoxShadow(color: widget.glow[1].withValues(alpha: widget.dark ? .45 : .32), blurRadius: 30, spreadRadius: -4, offset: const Offset(4, 16)),
              ],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: widget.gradient),
                ),
                child: Stack(children: [
                  Positioned.fill(
                    child: Image.asset('assets/images/texture.png',
                        fit: BoxFit.cover, color: Colors.white.withValues(alpha: .10), colorBlendMode: BlendMode.srcIn),
                  ),
                  // a thin light edge along the top
                  Positioned(left: 0, right: 0, top: 0, height: 1, child: ColoredBox(color: Colors.white.withValues(alpha: .35))),
                  Column(children: [
                    SizedBox(
                      height: 176,
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        Positioned(
                          top: 16,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [Color(0x66FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)], stops: [0, .55, .72]),
                            ),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 8))]),
                          child: SizedBox(
                            width: 134,
                            height: 160,
                            child: Image.asset(widget.art, fit: BoxFit.cover, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium),
                          ),
                        ),
                      ]),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
                      color: widget.foreground == Colors.white ? const Color(0x33000000) : const Color(0x38FFFFFF),
                      child: Column(children: [
                        Text(widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 16, color: widget.foreground)),
                        const SizedBox(height: 3),
                        Text(widget.sub,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 11.5, height: 1.3, color: widget.foreground.withValues(alpha: .88))),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
