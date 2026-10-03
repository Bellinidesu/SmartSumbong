// SmartSumbong — branch D building blocks.
//
// The pieces every D screen is made of, each one a part of the app
// preview: the contour background, the role-colour cards with their faint
// contour, the buttons, the vivid status steps, the round icon wells.

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'd_theme.dart';

extension DTr on BuildContext {
  /// English or Filipino for strings only branch D has.
  String tr(String en, String fil) => AppLocaleScope.of(this) == AppLocale.fil ? fil : en;
}

/// The contour lines (the Figma "Noise & Texture"), tinted for the page.
/// [full] runs them edge to edge at one strength (role picker, sign-in,
/// Home); otherwise they fade up from the bottom, as on the inner pages.
class DContour extends StatelessWidget {
  const DContour({super.key, this.full = false, this.colors});

  final bool full;
  final DColors? colors;

  @override
  Widget build(BuildContext context) {
    final d = colors ?? context.d;
    Widget img = Image.asset(
      'assets/images/texture.png',
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      color: d.contour.withValues(alpha: (d.contourAlpha * 1.6).clamp(0, 1)),
      colorBlendMode: BlendMode.srcIn,
      excludeFromSemantics: true,
    );
    if (!full) {
      img = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Color(0x80000000), Colors.transparent],
          stops: [0, .3, .62],
        ).createShader(r),
        child: img,
      );
    }
    return Positioned.fill(child: IgnorePointer(child: img));
  }
}

/// A D page: the page colour, the contour behind, the content in a SafeArea.
class DPage extends StatelessWidget {
  const DPage({
    super.key,
    required this.child,
    this.bottomBar,
    this.fullContour = false,
    this.colors,
    this.contour = true,
  });

  final Widget child;
  final Widget? bottomBar;
  final bool fullContour;
  final bool contour;
  final DColors? colors;

  @override
  Widget build(BuildContext context) {
    final d = colors ?? context.d;
    return Scaffold(
      backgroundColor: d.bg,
      bottomNavigationBar: bottomBar,
      body: Stack(children: [
        if (contour) DContour(full: fullContour, colors: d),
        SafeArea(bottom: bottomBar == null, child: child),
      ]),
    );
  }
}

/// The role-colour card (navy for residents, ink for tanods) with an
/// extremely faint contour — the preview's `.navycard`.
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.gradient,
    this.glow,
    this.radius = 22,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final List<Color>? gradient;

  /// A soft halo of this colour around the card (Emergency's cards).
  final Color? glow;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final g = gradient ?? [d.card1, d.card2];
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          if (glow != null) BoxShadow(color: glow!.withValues(alpha: d.dark ? .32 : .26), blurRadius: 26, spreadRadius: -2, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withValues(alpha: d.dark ? .35 : .14), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset('assets/images/texture.png',
                      fit: BoxFit.cover,
                      color: Colors.white.withValues(alpha: .06),
                      colorBlendMode: BlendMode.srcIn,
                      excludeFromSemantics: true),
                ),
              ),
              Padding(
                padding: padding,
                child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
              ),
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
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: borderColor ?? d.line, width: 1.2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

enum DButtonKind { orange, white, accent, ghost, green, greenLine, danger, line }

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
  });

  final String label;
  final VoidCallback? onTap;
  final DButtonKind kind;
  final bool small;
  final IconData? icon;
  final bool expand;
  final double? height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final (Color bg, Color fg, Color? side) = switch (kind) {
      DButtonKind.orange => (DColors.orange, const Color(0xFF141B34), null),
      DButtonKind.white => (Colors.white, d.tanod ? const Color(0xFF14181D) : DColors.brandNavy, null),
      DButtonKind.accent => (d.accent, d.bg, null),
      DButtonKind.ghost => (Colors.transparent, d.ink, d.line),
      DButtonKind.green => (DColors.greenVivid, Colors.white, null),
      DButtonKind.greenLine => (Colors.transparent, d.dark ? const Color(0xFF5FD68A) : DColors.green, d.dark ? const Color(0xFF3DBE6E) : DColors.green),
      DButtonKind.danger => (Colors.transparent, d.dark ? const Color(0xFFFF8A8A) : DColors.red, d.dark ? const Color(0xFF8E3A3A) : const Color(0xFFE7B4B4)),
      DButtonKind.line => (Colors.transparent, d.link, d.link),
    };
    final h = height ?? (small ? 38.0 : 50.0);
    final glow = kind == DButtonKind.orange || kind == DButtonKind.green;
    final child = busy
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: small ? 16 : 18, color: fg), const SizedBox(width: 7)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: small ? 14 : 16, color: fg)),
            ),
          ]);
    return Opacity(
      opacity: onTap == null && !busy ? .5 : 1,
      child: Container(
        height: h,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(small ? 11 : 14),
          boxShadow: glow && onTap != null
              ? [BoxShadow(color: bg.withValues(alpha: .32), blurRadius: 16, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(small ? 11 : 14),
            side: side == null ? BorderSide.none : BorderSide(color: side, width: kind == DButtonKind.ghost ? 1.5 : 2),
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

/// An icon, a line and an optional second line (the report's detail rows).
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: divider ? BoxDecoration(border: Border(bottom: BorderSide(color: d.line))) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: d.link),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: DType.body(d.ink, size: 14, w: FontWeight.w600)),
              if (sub != null) Text(sub!, style: DType.body(d.muted, size: 12)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
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
        borderRadius: BorderRadius.circular(14),
        color: Color.alphaBlend(DColors.orange.withValues(alpha: .12), d.card),
        border: Border.all(color: DColors.orange.withValues(alpha: .38)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: DType.body(d.ink, size: 13.5, w: FontWeight.w800))),
          if (time != null) Text(time!, style: DType.mono(d.muted, size: 11)),
        ]),
        const SizedBox(height: 3),
        Text(body, style: DType.body(d.ink, size: 14)),
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
      Text(title, style: DType.h1(d.accent)),
      if (lead != null) ...[
        const SizedBox(height: 6),
        Text(lead!, style: DType.body(d.muted, size: 14)),
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
    return Material(
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
    );
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
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: d.accent,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Center(child: Image.asset('assets/images/icon-bell.png', width: 22, height: 22, color: d.bg)),
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
