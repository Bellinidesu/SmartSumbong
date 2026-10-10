// SmartSumbong — branch D building blocks.
//
// The pieces every D screen is made of, each one a part of the app
// preview: the contour background, the role-colour cards with their faint
// contour, the buttons, the vivid status steps, the round icon wells.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'd_theme.dart';

extension DTr on BuildContext {
  /// English or Filipino for strings only branch D has.
  String tr(String en, String fil) => AppLocaleScope.of(this) == AppLocale.fil ? fil : en;
}

/// The preview's contour (`--tex`): a 1024 px line texture tiled at
/// [tile] logical px and tinted. [ContourKind.fade] is the inner pages
/// (strongest at the bottom, gone by mid-screen), [full] the role picker
/// and sign-in (even, .12), [home] the Homes (full height, .11, a touch
/// stronger toward the bottom).
enum ContourKind { fade, full, home }

class DContourTile extends StatelessWidget {
  const DContourTile({super.key, required this.color, this.tile = 420});

  final Color color;
  final double tile;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/contour.png',
        width: double.infinity,
        height: double.infinity,
        repeat: ImageRepeat.repeat,
        fit: BoxFit.none,
        alignment: Alignment.topLeft,
        scale: 1024 / tile,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      );
}

class DContour extends StatelessWidget {
  const DContour({super.key, this.kind = ContourKind.fade, this.colors});

  final ContourKind kind;
  final DColors? colors;

  @override
  Widget build(BuildContext context) {
    final d = colors ?? context.d;
    final alpha = switch (kind) {
      ContourKind.full => .12,
      ContourKind.home => d.dark ? d.contourAlpha : .11,
      ContourKind.fade => d.contourAlpha,
    };
    Widget w = DContourTile(color: d.contour.withValues(alpha: alpha));
    if (kind != ContourKind.full) {
      final home = kind == ContourKind.home;
      w = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: home
              ? const [Colors.black, Color(0xBF000000), Color(0x73000000)]
              : const [Colors.black, Color(0x80000000), Color(0x00000000)],
          stops: home ? const [0, .5, 1] : const [0, .25, .55],
        ).createShader(r),
        child: w,
      );
    }
    return Positioned.fill(child: IgnorePointer(child: w));
  }
}

/// A D page: the page colour, the contour behind, the content in a SafeArea.
class DPage extends StatelessWidget {
  const DPage({
    super.key,
    required this.child,
    this.bottomBar,
    this.fullContour = false,
    this.homeContour = false,
    this.colors,
    this.contour = true,
  });

  final Widget child;
  final Widget? bottomBar;
  final bool fullContour;
  final bool homeContour;
  final bool contour;
  final DColors? colors;

  @override
  Widget build(BuildContext context) {
    final d = colors ?? context.d;
    // The page shows behind the system buttons; they take the colour that
    // reads on it (a bottom bar sets its own, DBar).
    final light = d.bg.computeLuminance() > .5;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
        statusBarBrightness: light ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: d.bg,
        bottomNavigationBar: bottomBar,
        body: Stack(children: [
          if (contour)
            DContour(kind: homeContour ? ContourKind.home : (fullContour ? ContourKind.full : ContourKind.fade), colors: d),
          SafeArea(bottom: bottomBar == null, child: child),
        ]),
      ),
    );
  }
}

/// The role-colour card (`.navycard`): the gradient, radius 22, and a
/// contour so faint ([texAlpha], .018) it is only felt.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.gradient,
    this.glow,
    this.radius = 22,
    this.onTap,
    this.texAlpha = .018,
  });

  final Widget child;
  final EdgeInsets padding;
  final List<Color>? gradient;

  /// A soft halo of this colour around the card (Emergency's cards).
  final Color? glow;
  final double radius;
  final VoidCallback? onTap;
  final double texAlpha;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final g = gradient ?? [d.card1, d.card2];
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: glow == null ? null : [BoxShadow(color: glow!.withValues(alpha: .32), blurRadius: 12, spreadRadius: 1)],
      ),
      child: Material(
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g)),
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Positioned.fill(child: IgnorePointer(child: DContourTile(color: Colors.white.withValues(alpha: texAlpha), tile: 300))),
              Padding(padding: padding, child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A plain white (night: dark) card with a hairline edge.
class DSheet extends StatelessWidget {
  const DSheet({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.radius = 16, this.borderColor});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final r = BorderRadius.circular(radius);
    return Material(
      color: d.card,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: borderColor ?? d.line, width: 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

enum DButtonKind { orange, white, accent, ghost, green, greenLine, danger, red, line }

/// The preview's `.btn`: 44 high, radius 12, 15/800; `.sm` is 34, 10,
/// 13.5. Orange carries its soft glow.
class DButton extends StatelessWidget {
  const DButton(
    this.label, {
    super.key,
    required this.onTap,
    this.kind = DButtonKind.orange,
    this.small = false,
    this.icon,
    this.expand = false,
    this.height,
    this.busy = false,
    this.radius,
    this.fontSize,
    this.textColour,
  });

  final String label;
  final VoidCallback? onTap;
  final DButtonKind kind;
  final Color? textColour;
  final bool small;
  final IconData? icon;
  final bool expand;
  final double? height;
  final bool busy;
  final double? radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final (Color bg, Color fg0, Color? side) = switch (kind) {
      DButtonKind.orange => (DColors.orange, const Color(0xFF141B34), null),
      DButtonKind.white => (Colors.white, d.tanod ? const Color(0xFF14181D) : DColors.brandNavy, null),
      DButtonKind.accent => (d.btn, Colors.white, null),
      DButtonKind.ghost => (Colors.transparent, d.ink, d.line),
      DButtonKind.green => (DColors.greenVivid, Colors.white, null),
      DButtonKind.greenLine => (Colors.transparent, d.dark ? const Color(0xFF5FD68A) : DColors.green, d.dark ? const Color(0xFF3DBE6E) : DColors.green),
      DButtonKind.danger => (Colors.transparent, const Color(0xFFC62828), const Color(0xFFE7B4B4)),
      DButtonKind.red => (const Color(0xFFE5383B), Colors.white, null),
      DButtonKind.line => (Colors.transparent, d.link, d.link),
    };
    final fg = textColour ?? fg0;
    final h = height ?? (small ? 34.0 : 44.0);
    final rad = radius ?? (small ? 10.0 : 12.0);
    final glow = kind == DButtonKind.orange || kind == DButtonKind.green;
    final child = busy
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: small ? 16 : 18, color: fg), const SizedBox(width: 8)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: fontSize ?? (small ? 13.5 : 15), color: fg)),
            ),
          ]);
    final enabled = onTap != null && !busy;
    // Accessibility (WCAG 2.5.5 / Apple's 44 pt): the area a finger or a
    // screen reader can use is at least 44 high, however small the button
    // looks. The extra is invisible and taps there count as the button.
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: _visual(enabled, h, rad, bg, side, glow, child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visual(bool enabled, double h, double rad, Color bg, Color? side, bool glow, Widget child) {
    return Opacity(
      opacity: onTap == null && !busy ? .5 : 1,
      child: Container(
        height: h,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rad),
          boxShadow: glow && onTap != null ? [BoxShadow(color: bg.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 6))] : null,
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rad),
            side: side == null ? BorderSide.none : BorderSide(color: side, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four dispatch steps in their vivid colours: filled with a glow when
/// done, the next one pulsing in its colour, the line running through all
/// four. [captions] go under the labels (times, "Awaiting approval").
class DSteps extends StatefulWidget {
  const DSteps({super.key, required this.step, required this.labels, this.captions = const []});

  /// 0 = Accepted … 3 = Resolved.
  final int step;
  final List<String> labels;
  final List<String?> captions;

  @override
  State<DSteps> createState() => _DStepsState();
}

class _DStepsState extends State<DSteps> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final cs = d.steps;
    final n = widget.step;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final seg = w / 4;
      return Stack(children: [
        // the track and the coloured run
        Positioned(
          left: seg / 2,
          right: seg / 2,
          top: 12,
          height: 3,
          child: Container(color: d.line),
        ),
        Positioned(
          left: seg / 2,
          top: 12,
          height: 3,
          width: (w - seg) * (n.clamp(0, 3) / 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: cs),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Column(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) {
                      final done = i <= n, now = i == n + 1;
                      return Container(
                        width: 27,
                        height: 27,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? cs[i] : d.card,
                          border: Border.all(color: done || now ? cs[i] : d.line, width: 3),
                          boxShadow: [
                            if (done) BoxShadow(color: cs[i].withValues(alpha: .45), blurRadius: 12, offset: const Offset(0, 4)),
                            if (now) BoxShadow(color: cs[i].withValues(alpha: .25 - .17 * _pulse.value), spreadRadius: 4 + 5 * _pulse.value),
                          ],
                        ),
                        child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(widget.labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          color: i <= n ? cs[i] : (i == n + 1 ? d.ink : d.muted))),
                  if (i < widget.captions.length && widget.captions[i] != null)
                    Text(widget.captions[i]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 10.5, color: d.muted)),
                ]),
              ),
          ],
        ),
      ]);
    });
  }
}

/// A small round well holding an icon (detail rows, the three actions on
/// a dispatch order).
class DWell extends StatelessWidget {
  const DWell(this.icon, {super.key, this.size = 42, this.color, this.tint});

  final IconData icon;
  final double size;
  final Color? color;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tint ?? d.field, border: Border.all(color: d.line)),
      child: Icon(icon, size: size * .48, color: color ?? d.link),
    );
  }
}

/// `.rows li`: a 20 px icon, the line 13.5, an optional second line 12 in
/// muted, 9 px above and below, a hairline under it.
class DRow extends StatelessWidget {
  const DRow({super.key, required this.icon, required this.title, this.sub, this.trailing, this.onTap, this.divider = true});

  final IconData icon;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: divider ? BoxDecoration(border: Border(bottom: BorderSide(color: d.line))) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: d.link),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: DType.body(d.ink, size: 13.5, w: FontWeight.w400).copyWith(height: 1.3)),
              if (sub != null) Text(sub!, style: DType.body(d.muted, size: 12, w: FontWeight.w400).copyWith(height: 1.3)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// `.shero`: the category colour as a radial wash — light at the top
/// left, the colour in the middle, a darker corner — with the contour at
/// .045 over it. Children (the chip, the back and close buttons) go in a
/// stack on top.
class DHero extends StatelessWidget {
  const DHero({super.key, required this.colour, required this.height, this.radius = 0, this.glyph, this.children = const []});

  final Color colour;
  final double height;
  final double radius;

  /// The category's own symbol, the one on its map pin, drawn large and
  /// faint at the right (Ace, 7 Oct 2026).
  final IconData? glyph;
  final List<Widget> children;

  static BoxDecoration decoration(Color cs) => BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.6, -.8),
          radius: 1.2,
          colors: [Color.lerp(Colors.white, cs, .55)!, cs, Color.lerp(Colors.black, cs, .7)!],
          stops: const [0, .6, 1],
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: decoration(colour))),
            Positioned.fill(child: IgnorePointer(child: DContourTile(color: Colors.white.withValues(alpha: .045), tile: 300))),
            if (glyph != null)
              Positioned(
                right: -height * .08,
                bottom: -height * .1,
                child: IgnorePointer(child: Icon(glyph, size: height * .78, color: Colors.white.withValues(alpha: .16))),
              ),
            ...children,
          ]),
        ),
      );
}

/// The category chip on a hero: Inter 700 11 on a dark glass pill.
class DHeroChip extends StatelessWidget {
  const DHeroChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white)),
      );
}

/// A round dark-glass button on a hero (back, share, close).
class DHeroButton extends StatelessWidget {
  const DHeroButton({super.key, required this.icon, required this.onTap, this.size = 36});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), shape: BoxShape.circle),
          child: Icon(icon, size: size * .56, color: Colors.white),
        ),
      );
}

/// `ol.steps`: a vertical list whose dots and joining line fill with the
/// category colour as far as the case has got. [subs] sit under a label.
class DStepList extends StatelessWidget {
  const DStepList({super.key, required this.labels, required this.on, required this.colour, this.subs = const {}});

  final List<String> labels;
  final int on;
  final Color colour;
  final Map<int, String> subs;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Column(children: [
      for (var i = 0; i < labels.length; i++)
        Stack(children: [
          if (i < labels.length - 1) Positioned(left: 8, top: 16, bottom: 0, width: 2, child: ColoredBox(color: i < on ? colour : d.line)),
          Positioned(
            left: 3,
            top: 3,
            child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: i < on ? colour : d.card, border: Border.all(color: i < on ? colour : d.line, width: 2))),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(labels[i], style: DType.body(i < on ? d.ink : d.muted, size: 13.5, w: i < on ? FontWeight.w700 : FontWeight.w400).copyWith(height: 1.3)),
                if (subs[i] != null) Text(subs[i]!, style: DType.body(d.muted, size: 11.5).copyWith(height: 1.3)),
              ]),
            ),
          ),
        ]),
    ]);
  }
}

/// The amber box: barangay instructions, admin directives.
class DNote extends StatelessWidget {
  const DNote({super.key, required this.title, required this.body, this.time});

  final String title;
  final String body;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Color.alphaBlend(DColors.orange.withValues(alpha: .12), d.card),
        border: Border.all(color: DColors.orange.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: DType.body(d.ink, size: 13, w: FontWeight.w700).copyWith(height: 1.45))),
          if (time != null) Text(time!, style: DType.mono(d.muted, size: 11)),
        ]),
        const SizedBox(height: 2),
        Text(body, style: DType.body(d.ink, size: 13, w: FontWeight.w400).copyWith(height: 1.45)),
      ]),
    );
  }
}

/// Page title block used on the inner pages: a heading and a lead line.
class DHeading extends StatelessWidget {
  const DHeading(this.title, {super.key, this.lead});

  final String title;
  final String? lead;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: DType.h1(d.ink)),
      if (lead != null) ...[
        const SizedBox(height: 6),
        Text(lead!, style: DType.body(d.ink2, size: 13.5)),
      ],
    ]);
  }
}

/// The round back button at the top-left of inner pages.
class DBack extends StatelessWidget {
  const DBack({super.key, this.onTap, this.onImage = false});

  final VoidCallback? onTap;

  /// Sitting on a photo or map: dark glass instead of the page well.
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      excludeSemantics: true,
      child: Material(
      color: onImage ? Colors.black.withValues(alpha: .38) : d.card,
      shape: CircleBorder(side: onImage ? BorderSide.none : BorderSide(color: d.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.chevron_left_rounded, size: 26, color: onImage ? Colors.white : d.ink),
        ),
      ),
    ));
  }
}

/// The notification bell: a role-colour circle, the unread count on it.
class DBell extends StatelessWidget {
  const DBell({super.key, required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      container: true,
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // 40 drawn, 44 to touch (accessibility).
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: d.btn),
            child: Center(child: Image.asset('assets/images/icon-bell.png', width: 22, height: 22, color: Colors.white)),
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                decoration: BoxDecoration(color: const Color(0xFFE5383B), borderRadius: BorderRadius.circular(99), border: Border.all(color: d.bg, width: 2)),
                child: Center(
                  widthFactor: 1,
                  child: Text(unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 10, color: Colors.white)),
                ),
              ),
            ),
        ]),
        ),
      ),
    );
  }
}

/// A D dialog: a rounded card on the page colour, a heading, a line, and
/// one or two buttons. Returns true for [primary], false for [secondary].
Future<bool?> showDDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String primary,
  String? secondary,
  DButtonKind primaryKind = DButtonKind.orange,
  IconData? icon,
  Color? iconColor,
  Widget? preview,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (ctx) {
      final d = ctx.d;
      return Dialog(
        backgroundColor: d.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (icon != null) ...[
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: (iconColor ?? DColors.orange).withValues(alpha: .14)),
                  child: Icon(icon, color: iconColor ?? DColors.orange, size: 28),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (preview != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(16), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 200), child: preview)),
              const SizedBox(height: 14),
            ],
            Text(title, textAlign: TextAlign.center, style: DType.h2(d.ink)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: DType.body(d.ink2, size: 14)),
            ],
            const SizedBox(height: 18),
            DButton(primary, kind: primaryKind, expand: true, onTap: () => Navigator.of(ctx).pop(true)),
            if (secondary != null) ...[
              const SizedBox(height: 8),
              DButton(secondary, kind: DButtonKind.ghost, expand: true, onTap: () => Navigator.of(ctx).pop(false)),
            ],
          ]),
        ),
      );
    },
  );
}

/// One choice on a pick-one page (Languages, Appearance).
class DOption {
  const DOption({required this.title, this.sub, this.leading, required this.selected, required this.onTap});

  final String title;
  final String? sub;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;
}

/// A pick-one page: back, the heading, the choices as white cards with
/// a radio that fills in the role colour.
class DOptionsPage extends StatelessWidget {
  const DOptionsPage({super.key, required this.title, this.lead, required this.options});

  final String title;
  final String? lead;
  final List<DOption> options;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return DPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          const Align(alignment: Alignment.centerLeft, child: DBack()),
          const SizedBox(height: 12),
          DHeading(title, lead: lead),
          const SizedBox(height: 18),
          for (final o in options) ...[
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: o.selected,
              button: true,
              child: DSheet(
                onTap: o.onTap,
                borderColor: o.selected ? d.accent : null,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(children: [
                  if (o.leading != null) ...[o.leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.title, style: DType.body(d.ink, size: 15.5, w: FontWeight.w800)),
                      if (o.sub != null) Text(o.sub!, style: DType.body(d.muted, size: 12.5)),
                    ]),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: o.selected ? d.accent : d.line, width: o.selected ? 7 : 2),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// The app's on/off toggle: green when on, grey when off, a white knob.
/// One look everywhere (Notification Preferences, the anonymous switch).
class DToggle extends StatelessWidget {
  const DToggle({super.key, required this.on, required this.onTap, this.label});

  final bool on;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: on,
        label: label,
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: onTap == null ? .5 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: on ? const Color(0xFF1F8A45) : const Color(0xFFC8CEDB), borderRadius: BorderRadius.circular(99)),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))]),
              ),
            ),
          ),
        ),
      );
}
