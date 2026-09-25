// SmartSumbong — role picker.
//
// Figma: RESIDENT OR RESPONDER.
//
// Sits between onboarding and login, and is where "Back to Roles" on the
// login screen returns to.
//
// The tanod card is drawn but inert in this build. Residents and tanods
// are separate clients, and the tanod app does not exist yet — see the
// note on the tap handler for why it says so out loud rather than
// silently ignoring the press.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  // Figma RESIDENT OR RESPONDER: the logo art in its 403x337 box at 122,
  // "What’s your role?" 36/800 at 501, and two 160x210 cards 20 apart
  // at 566 — navy for the resident, orange for the tanod — radius 50
  // with a 1px light edge and the design shadow, each with its figure
  // (Kim's art) and a 16/700 underlined label at 161.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Stack(
        children: [
          const FigmaTexture(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: figmaTop(context, 122), bottom: 24),
              child: Column(
                children: [
                  const FigmaLogo(visibleHeight: 337),
                  const SizedBox(height: 42),
                  Text(
                    s.roleTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w800,
                      fontSize: 36,
                      height: 56.16 / 36,
                      color: context.colors.navy,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoleCard(
                        label: s.roleResident,
                        asset: 'assets/images/residenthd.png',
                        fallback: Icons.person,
                        background: context.colors.navy,
                        foreground: context.colors.bg,
                        onTap: () =>
                            Navigator.of(context).pushNamed('/login'),
                      ),
                      const SizedBox(width: 20),
                      _RoleCard(
                        label: s.roleTanod,
                        asset: 'assets/images/tanodhd.png',
                        fallback: Icons.local_police,
                        background: kFigmaOrange,
                        foreground: context.colors.bg,
                        // A tanod registers here and then uses the
                        // separate tanod app. Registration lives in this
                        // app because it is the one a person installs
                        // first, and because the signup path — trigger,
                        // verification queue, admin approval — is the
                        // same one either role goes through.
                        //
                        // The admin checks the Barangay ID against the
                        // barangay's own roster. That is the whole
                        // control for a staff account, and it is why
                        // self-registration is safe here: nobody becomes
                        // a tanod without a person who knows the roster
                        // saying so.
                        onTap: () => Navigator.of(context)
                            .pushNamed('/register-tanod'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.asset,
    required this.fallback,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final String asset;
  final IconData fallback;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Two 160-wide cards and the 20 gap fit a 340 screen; narrower than
    // that they shrink together rather than overflow.
    final w = ((MediaQuery.sizeOf(context).width - 40 - 20) / 2)
        .clamp(120.0, 160.0);
    final h = w * 210 / 160;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          boxShadow: kFigmaShadow,
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: BorderSide(color: context.colors.bg),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            // The frame's figure box is 104 tall starting 36 down; the
            // label sits at 161.
            child: Column(
              children: [
                SizedBox(height: h * 36 / 210),
                SizedBox(
                  height: h * 104 / 210,
                  child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) =>
                          Icon(fallback, size: 74, color: foreground),
                    ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, h * 24 / 210),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: foreground,
                      decoration: TextDecoration.underline,
                      decorationColor: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
