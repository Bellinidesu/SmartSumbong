// SmartSumbong — first-launch onboarding.
//
// Figma: ONBOARDING -1 through ONBOARDING - 4.
//
// Shown once, on the first launch of a fresh install, before the login
// screen. The flag lives in shared_preferences rather than on the
// account: it is a property of this handset, not of the resident, and a
// resident who reinstalls after a phone reset should see the
// introduction again.
//
// Skip and Start do the same thing. Skip is not an escape hatch that
// leaves something undone — the four screens are an explanation, and a
// resident who does not want one should not have to tap through it.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../theme.dart';

/// Set once the resident has seen or skipped the introduction.
const onboardingSeenKey = 'onboarding_seen';

class _Page {
  const _Page({
    required this.title,
    required this.body,
    this.image,
    this.wordmark = false,
  });

  final String Function(Strings s) title;
  final String Function(Strings s) body;
  final String? image;

  /// The first page leads with the logo rather than an illustration.
  final bool wordmark;
}

const _pages = <_Page>[
  _Page(
    wordmark: true,
    title: _title1,
    body: _body1,
  ),
  _Page(
    image: 'assets/images/OB2.png',
    title: _title2,
    body: _body2,
  ),
  _Page(
    image: 'assets/images/OB3.png',
    title: _title3,
    body: _body3,
  ),
  _Page(
    image: 'assets/images/OB4.png',
    title: _title4,
    body: _body4,
  ),
];

// Static functions rather than closures so `_pages` can stay a `const`
// list \u2014 the copy itself still comes from [Strings], so it still
// switches with the language.
String _title1(Strings s) => s.onboardTitle1;
String _body1(Strings s) => s.onboardBody1;
String _title2(Strings s) => s.onboardTitle2;
String _body2(Strings s) => s.onboardBody2;
String _title3(Strings s) => s.onboardTitle3;
String _body3(Strings s) => s.onboardBody3;
String _title4(Strings s) => s.onboardTitle4;
String _body4(Strings s) => s.onboardBody4;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    // Write the flag before navigating. If this throws — storage full,
    // or a platform channel that is not ready — the resident still
    // reaches login; they simply see the introduction again next time,
    // which is the harmless failure.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(onboardingSeenKey, true);
    } catch (_) {
      // Deliberately ignored. See above.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/roles');
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          // The same contour texture as the launch gate and home, so the
          // first four screens and the fifth read as one surface.
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
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _PageView(page: _pages[i]),
                  ),
                ),

                _Dots(count: _pages.length, active: _index),
                const SizedBox(height: 28),

                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 0, 36, 32),
                  child: Row(
                    mainAxisAlignment: _index == 0
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.spaceBetween,
                    children: [
                      // The first page has no Skip in the design: there
                      // is nothing yet to skip past.
                      if (_index > 0)
                        _PillButton(
                          label: context.s.onboardSkip,
                          filled: false,
                          onTap: _finish,
                        ),
                      _PillButton(
                        label: last ? context.s.onboardStart : context.s.onboardNext,
                        filled: true,
                        onTap: _next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: page.wordmark
                  ? FractionallySizedBox(
                      widthFactor: 0.78,
                      child: Image.asset(
                        'assets/images/logo-wordmark.png',
                        semanticLabel: 'SmartSumbong',
                        filterQuality: FilterQuality.medium,
                      ),
                    )
                  : Image.asset(
                      page.image!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      // The illustrations carry no information the copy
                      // below does not already state, so a screen reader
                      // should skip straight to the heading.
                      excludeFromSemantics: true,
                    ),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            page.title(s),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1.2,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            page.body(s),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Tokens.navy,
            ),
          ),

          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= active ? Tokens.navy : Tokens.divider,
            ),
          ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 38,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.navy,
                foregroundColor: Tokens.bg,
                minimumSize: const Size(108, 38),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.pill),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                backgroundColor: Tokens.field,
                foregroundColor: Tokens.navy,
                side: const BorderSide(color: Tokens.navy),
                minimumSize: const Size(108, 38),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.pill),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: Text(label),
            ),
    );
  }
}
