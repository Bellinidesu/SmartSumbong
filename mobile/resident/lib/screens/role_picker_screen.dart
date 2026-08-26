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

class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: Image.asset(
                'assets/images/texture.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  FractionallySizedBox(
                    widthFactor: 0.78,
                    child: Image.asset(
                      'assets/images/logo-wordmark.png',
                      semanticLabel: 'SmartSumbong',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),

                  const Spacer(flex: 3),

                  Text(
                    s.roleTitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      color: Tokens.navy,
                    ),
                  ),
                  const SizedBox(height: 22),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoleCard(
                        label: s.roleResident,
                        asset: 'assets/images/residenthd.png',
                        fallback: Icons.person,
                        background: Tokens.navy,
                        foreground: Tokens.bg,
                        onTap: () =>
                            Navigator.of(context).pushNamed('/login'),
                      ),
                      const SizedBox(width: 16),
                      _RoleCard(
                        label: s.roleTanod,
                        asset: 'assets/images/tanodhd.png',
                        fallback: Icons.local_police,
                        background: const Color(0xFFFF9800),
                        foreground: Tokens.navy,
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

                  const Spacer(flex: 5),
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
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shadowColor: const Color(0x4D121212),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 124,
            height: 158,
            // A column, not a stack: the label has to have card colour
            // behind it. Overlaid on the figure, white-on-white makes
            // it disappear on the resident card.
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      excludeFromSemantics: true,
                      // The source is a 3x export being drawn into a
                      // 124pt card. Default bilinear sampling softens a
                      // downscale that large; medium enables mipmaps.
                      filterQuality: FilterQuality.medium,
                      // Until the figures are exported, a Material icon
                      // in the right colour keeps the screen usable
                      // instead of rendering a broken-image box.
                      errorBuilder: (_, __, ___) =>
                          Icon(fallback, size: 74, color: foreground),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
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
