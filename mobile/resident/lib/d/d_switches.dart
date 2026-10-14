// SmartSumbong — the day/night switch and the EN/PH flags (branch D).
//
// Ported value by value from the app preview's `.dn` and `.flags` CSS:
// a 52x28 sky that turns to starry night as the sun slides over and
// becomes the cratered moon; and a navy pill holding the two flags,
// the chosen one on white.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import 'd_ui.dart' show DTr;

class DDayNight extends StatelessWidget {
  const DDayNight({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Semantics(
      button: true,
      label: dark
          ? context.tr('Switch to light mode', 'Lumipat sa maliwanag na mode')
          : context.tr('Switch to dark mode', 'Lumipat sa madilim na mode'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => AppThemeScope.controllerOf(context).set(dark ? ThemeMode.light : ThemeMode.dark),
        // 52x28 drawn, 44 high to touch (accessibility).
        child: SizedBox(
          height: 44,
          child: Center(
            widthFactor: 1,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: dark ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              builder: (_, night, _) => CustomPaint(size: const Size(52, 28), painter: _DayNightPainter(night)),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayNightPainter extends CustomPainter {
  _DayNightPainter(this.night);

  final double night;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(99));
    canvas.save();
    canvas.clipRRect(r);
    // day sky
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8ED0FF), Color(0xFF4C9EF0)]).createShader(Offset.zero & size),
    );
    // night sky and stars, fading in
    if (night > 0) {
      canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: night));
      canvas.drawRect(
        Offset.zero & size,
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B1540), Color(0xFF24306E)]).createShader(Offset.zero & size),
      );
      final star = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(size.width * .22, size.height * .30), .8, star);
      canvas.drawCircle(Offset(size.width * .38, size.height * .68), .8, star);
      canvas.drawCircle(Offset(size.width * .14, size.height * .62), 1.1, star);
      canvas.restore();
    }
    // inset shadow at the top edge
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 3),
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59001E3C), Color(0x00001E3C)]).createShader(Rect.fromLTWH(0, 0, size.width, 3)),
    );
    canvas.restore();
    canvas.drawRRect(r.deflate(.75), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white.withValues(alpha: .55));

    // sun -> moon
    final c = Offset(3 + 11 + night * 24, 14);
    final body = Color.lerp(const Color(0xFFFFC83D), const Color(0xFFE6E9F4), night)!;
    final glow = Color.lerp(const Color(0x4DFFC83D), const Color(0x26C8D2FF), night)!;
    canvas.drawCircle(c, 15, Paint()..color = glow);
    canvas.drawCircle(c, 11, Paint()..color = body);
    if (night > 0) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(night * 200 * math.pi / 180);
      final crater = Paint()..color = const Color(0xFFC3C9DC).withValues(alpha: night);
      canvas.drawCircle(const Offset(-3.8, -3.6), 3.6, crater);
      canvas.drawCircle(const Offset(3.1, 2.6), 2.4, crater);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DayNightPainter old) => old.night != night;
}

class DFlags extends StatelessWidget {
  const DFlags({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = AppLocaleScope.of(context);
    Widget btn(AppLocale l, bool us, String code) {
      final on = lang == l;
      return Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 58),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: on ? 1 : .7,
              child: Container(
                width: 18,
                height: 12,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), boxShadow: const [BoxShadow(color: Color(0x26000000), spreadRadius: 1)]),
                child: ClipRRect(borderRadius: BorderRadius.circular(2), child: CustomPaint(painter: _FlagPainter(us))),
              ),
            ),
            const SizedBox(width: 6),
            Text(code, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .72, color: on ? const Color(0xFF00308F) : Colors.white)),
          ]),
      );
    }

    // The pill is drawn 34 high; each half is touched over the full 44
    // (accessibility), and read out as a selectable button.
    Widget half(AppLocale l, String label) => Expanded(
          child: Semantics(
            button: true,
            selected: lang == l,
            label: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppLocaleScope.controllerOf(context).set(l),
            ),
          ),
        );

    return SizedBox(
      height: 44,
      child: Stack(alignment: Alignment.center, children: [
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFF00308F), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [btn(AppLocale.en, true, 'EN'), btn(AppLocale.fil, false, 'PH')]),
          ),
        ),
        Positioned.fill(child: Row(children: [half(AppLocale.en, 'English'), half(AppLocale.fil, 'Filipino')])),
      ]),
    );
  }
}

/// A flag on its own, the preview's 46x31 on Languages (7 Oct 2026).
class DFlag extends StatelessWidget {
  const DFlag({super.key, required this.us, this.width = 46, this.height = 31});

  final bool us;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x1F000000), spreadRadius: 1)]),
        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: CustomPaint(painter: _FlagPainter(us))),
      );
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.us);

  final bool us;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 30, size.height / 20);
    final p = Paint();
    if (us) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 30, 20), p..color = const Color(0xFFB22234));
      p.color = Colors.white;
      for (var i = 0; i < 6; i++) {
        canvas.drawRect(Rect.fromLTWH(0, 1.54 + 3.077 * i, 30, 1.54), p);
      }
      canvas.drawRect(const Rect.fromLTWH(0, 0, 12.5, 10.77), p..color = const Color(0xFF3C3B6E));
    } else {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 30, 10), p..color = const Color(0xFF0038A8));
      canvas.drawRect(const Rect.fromLTWH(0, 10, 30, 10), p..color = const Color(0xFFCE1126));
      canvas.drawPath(Path()..moveTo(0, 0)..lineTo(17.32, 10)..lineTo(0, 20)..close(), p..color = Colors.white);
      canvas.drawCircle(const Offset(5.8, 10), 2, p..color = const Color(0xFFFCD116));
    }
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.us != us;
}

/// The pair, as they sit on the role picker and sign-in.
class DPrefsRow extends StatelessWidget {
  const DPrefsRow({super.key, this.colors});

  // ignore: unused_field
  final Object? colors;

  @override
  Widget build(BuildContext context) =>
      const Row(mainAxisSize: MainAxisSize.min, children: [DDayNight(), SizedBox(width: 8), DFlags()]);
}
