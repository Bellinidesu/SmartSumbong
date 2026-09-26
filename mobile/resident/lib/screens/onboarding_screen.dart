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
  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    final size = MediaQuery.sizeOf(context);
    final g = _Grid(size);

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

          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _PageView(
              page: _pages[i],
              grid: g,
              index: i,
              count: _pages.length,
            ),
          ),

          // The first page has no Skip in the design: there is nothing
          // yet to skip past.
          if (_index > 0)
            Positioned(
              left: g.x(46),
              top: g.y(769),
              child: _PillButton(
                label: context.s.onboardSkip,
                filled: false,
                onTap: _finish,
              ),
            ),
          Positioned(
            right: g.x(46),
            top: g.y(769),
            child: _PillButton(
              label: last ? context.s.onboardStart : context.s.onboardNext,
              filled: true,
              onTap: _next,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps the frames' 412x917 coordinates onto this screen.
class _Grid {
  const _Grid(this.size);

  final Size size;

  double x(double v) => v * size.width / 412;
  double y(double v) => v * size.height / 917;

  /// Square art keeps its shape: the smaller of the two scales.
  double side(double v) =>
      v * (size.width / 412 < size.height / 917
          ? size.width / 412
          : size.height / 917);
}

class _PageView extends StatelessWidget {
  const _PageView({
    required this.page,
    required this.grid,
    required this.index,
    required this.count,
  });

  final _Page page;
  final _Grid grid;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final g = grid;
    final art = g.side(page.artSize);

    return Stack(
      children: [
        Positioned(
          // Centred on the frame's box, so a narrower scale stays centred.
          left: g.x(page.artLeft + page.artSize / 2) - art / 2,
          top: g.y(page.artTop + page.artSize / 2) - art / 2,
          width: art,
          height: art,
          // Decoded at the size drawn (branch B): the art is 2048 px
          // square, about 17 MB in memory at full size, for a box a third
          // of that on screen.
          child: page.wordmark
              ? Image.asset(
                  page.image,
                  semanticLabel: 'SmartSumbong',
                  filterQuality: FilterQuality.medium,
                  cacheWidth:
                      (art * MediaQuery.devicePixelRatioOf(context)).round(),
                )
              : Image.asset(
                  page.image,
                  fit: BoxFit.contain,
                  cacheWidth:
                      (art * MediaQuery.devicePixelRatioOf(context)).round(),
                  filterQuality: FilterQuality.medium,
                  // The illustrations carry no information the copy
                  // below does not already state, so a screen reader
                  // should skip straight to the heading.
                  excludeFromSemantics: true,
                ),
        ),
        Positioned(
          left: g.x(45),
          right: g.x(45),
          top: g.y(page.wordmark ? 518 : 546),
          child: Column(
            children: [
              Text(
                page.title(s),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: page.wordmark ? 1.0 : 38 / 30,
                  color: context.colors.navy,
                ),
              ),
              SizedBox(height: page.wordmark ? 6 : 5),
              Text(
                page.body(s),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 20 / 16,
                  color: context.colors.navy,
                ),
              ),
              SizedBox(height: page.wordmark ? 20 : 32),
              _Dots(count: count, active: index),
            ],
          ),
        ),
      ],
    );
  }
}

/// The frame's dots: 13 across, 13 apart, navy up to the current page and
/// #BFBFBF after it.
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
            margin: const EdgeInsets.symmetric(horizontal: 6.5),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= active
                  ? context.colors.navy
                  : const Color(0xFFBFBFBF),
            ),
          ),
      ],
    );
  }
}

/// The frames' 114x44 pills: Next navy with a 1px #F3F3F3 edge, Skip
/// #FBFBFB with a navy edge, both 16/700 with the y5 / blur 5 shadow.
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
    const size = Size(114, 44);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.pill),
    );
    const text = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 16,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.pill),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 3.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.navy,
                foregroundColor: context.colors.bg,
                fixedSize: size,
                minimumSize: size,
                padding: EdgeInsets.zero,
                elevation: 0,
                side: BorderSide(color: context.colors.bg),
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                backgroundColor: context.colors.field,
                foregroundColor: context.colors.navy,
                side: BorderSide(color: context.colors.navy),
                fixedSize: size,
                minimumSize: size,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            ),
    );
  }
}
