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

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

/// Set once the resident has seen or skipped the introduction.
const onboardingSeenKey = 'onboarding_seen';

class _Page {
  const _Page({
    required this.title,
    required this.body,
    required this.image,
    required this.artLeft,
    required this.artTop,
    required this.artSize,
    this.wordmark = false,
  });

  final String Function(Strings s) title;
  final String Function(Strings s) body;
  final String image;

  /// Where the frame puts the (square) art, in 412x917 frame units.
  final double artLeft;
  final double artTop;
  final double artSize;

  /// The first page leads with the logo rather than an illustration, and
  /// its two-line title sits higher (518 rather than 546).
  final bool wordmark;
}

const _pages = <_Page>[
  // Art boxes from the frames. Page 1's 403x337 FILL rectangle at y=192
  // shows the square logo art 403 wide, centred, so its square starts 33
  // higher.
  _Page(
    wordmark: true,
    image: 'assets/images/onboarding-logo.png',
    artLeft: 5,
    artTop: 159,
    artSize: 403,
    title: _title1,
    body: _body1,
  ),
  _Page(
    image: 'assets/images/OB2.png',
    artLeft: 10,
    artTop: 164,
    artSize: 391,
    title: _title2,
    body: _body2,
  ),
  _Page(
    image: 'assets/images/OB3.png',
    artLeft: 39,
    artTop: 191,
    artSize: 347,
    title: _title3,
    body: _body3,
  ),
  _Page(
    image: 'assets/images/OB4.png',
    artLeft: 7,
    artTop: 158,
    artSize: 397,
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

  // Figma ONBOARDING -1 to - 4, laid out in the frames' 412x917
  // coordinates scaled to the screen: art at each frame's own box, the
  // 30/800 title at 546 (518 for the two-line welcome), the 16/500 body
  // under it, the 13px dots grouped with the text as in the frames (so
  // they land at 663 in English and move down, not into the copy, when a
  // translation runs longer), and 114x44 Skip / Next at 769, 46 in from
  // each side. Skip is absent on the first page, as in its frame.
  // Branch D: the full contour behind; each page the art over a soft
  // halo, the heading and the line under it, the dots (the current one
  // stretched), and Skip / Next pinned at the bottom.
  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    final d = context.dResident;
    return DPage(
      colors: d,
      fullContour: true,
      child: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _PageView(page: _pages[i]),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _pages.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _index ? 26 : 9,
              height: 9,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: i <= _index ? d.accent : d.line),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Row(children: [
            // The first page has no Skip: there is nothing yet to skip past.
            if (_index > 0) Expanded(child: DButton(context.s.onboardSkip, kind: DButtonKind.ghost, expand: true, onTap: _finish)),
            if (_index > 0) const SizedBox(width: 10),
            Expanded(child: DButton(last ? context.s.onboardStart : context.s.onboardNext, expand: true, onTap: _next)),
          ]),
        ),
      ]),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.dResident;
    return LayoutBuilder(builder: (context, box) {
      final art = (box.maxHeight * .48).clamp(160.0, 330.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 12),
        child: Column(children: [
          SizedBox(
            height: art + 20,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: art,
                height: art,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    d.accent.withValues(alpha: d.dark ? .22 : .12),
                    d.accent.withValues(alpha: 0),
                  ]),
                ),
              ),
              Image.asset(
                page.image,
                width: art,
                height: art,
                fit: BoxFit.contain,
                cacheWidth: (art * MediaQuery.devicePixelRatioOf(context)).round(),
                filterQuality: FilterQuality.medium,
                semanticLabel: page.wordmark ? 'SmartSumbong' : null,
                // The illustrations carry no information the copy below
                // does not already state.
                excludeFromSemantics: !page.wordmark,
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(page.title(s), textAlign: TextAlign.center, style: DType.h1(d.accent).copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          Text(page.body(s), textAlign: TextAlign.center, style: DType.body(d.ink2, size: 15.5)),
        ]),
      );
    });
  }
}
