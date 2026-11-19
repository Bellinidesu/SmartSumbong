// SmartSumbong — the pieces of the resident's Map tab, as the Map tab artifact draws them (20 Nov 2026): the filter chips
// that are also the legend, the round Frame 183 button and the Layers button, the Layers bottom sheet, the small card a
// pin opens and the portal-style case card it expands into, the progress track, and the notes the tab says when there is
// nothing to draw. What they say is the screen's; this file only lays it out.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import 'category_card.dart' show concernFill;
import 'd_form.dart';
import 'map_glyphs.dart';

/// The artifact's own outline icons (its Icon component, 24 px, 2 px round), for the controls it draws.
abstract final class MapTabIcons {
  static const locate = MapGlyph(['M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22'], [(12, 12, 3), (12, 12, 7.5)]);
  static const megaphone = MapGlyph([
    'M3.5 10.5v3a1 1 0 0 0 1 1H7l5.5 4.5V5L7 9.5H4.5a1 1 0 0 0-1 1z',
    'M16 9a4.5 4.5 0 0 1 0 6M18.8 6.5a8.5 8.5 0 0 1 0 11',
  ]);
  static const layers = MapGlyph(['M12 3.5l9 5-9 5-9-5z', 'M3 12.5l9 5 9-5', 'M3 16.5l9 5 9-5']);
  static const map = MapGlyph(['M9 4L3.5 6v14L9 18l6 2 5.5-2V4L15 6zM9 4v14M15 6v14']);
  static const hall = MapGlyph(['M3 21h18M5 21V10l7-5.5L19 10v11M9.5 21v-5.5h5V21']);
  static const pin = MapGlyph(['M12 21s7-6.2 7-11.5a7 7 0 1 0-14 0C5 14.8 12 21 12 21z'], [(12, 9.5, 2.5)]);
  static const check = MapGlyph(['M5 12.5l4.5 4.5L19 7.5']);
  static const close = MapGlyph(['M6 6l12 12M18 6L6 18']);
}

/// The artifact's "contrast" icon: a circle with its right half filled.
class MapContrastIcon extends StatelessWidget {
  const MapContrastIcon({super.key, this.size = 26, required this.colour});

  final double size;
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _ContrastPainter(colour)));
}

class _ContrastPainter extends CustomPainter {
  const _ContrastPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(12, 12), 8.5, line);
    canvas.drawLine(const Offset(12, 3.5), const Offset(12, 20.5), line);
    final half = Path()
      ..moveTo(12, 3.5)
      ..arcToPoint(const Offset(12, 20.5), radius: const Radius.circular(8.5))
      ..close();
    canvas.drawPath(half, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_ContrastPainter old) => old.colour != colour;
}

/// The shadow under a control or card over the map (the artifact's --shadow).
List<BoxShadow> _lift(DColors d, {double blur = 10, double dy = 2}) => [
      BoxShadow(color: d.dark ? const Color(0x80000000) : const Color(0x33141B34), blurRadius: blur, offset: Offset(0, dy)),
    ];

// ---------- the filter chips -------------------------------------------

/// One chip of the row under the top box: "My reports", "Notices", then a category with its colour dot and count.
class MapChipData {
  const MapChipData({required this.id, required this.label, required this.count, this.dot, this.glyph, this.selected = false}) : divider = false;

  const MapChipData.divider()
      : id = '',
        label = '',
        count = 0,
        dot = null,
        glyph = null,
        selected = false,
        divider = true;

  final String id;
  final String label;
  final int count;

  /// A category's colour.
  final Color? dot;

  /// A source's icon (the megaphone of Notices).
  final MapGlyph? glyph;
  final bool selected;
  final bool divider;
}

/// The row of filter chips: the legend and the filter in one. It scrolls sideways; a fade at the edge says there is more.
class MapFilterChips extends StatefulWidget {
  const MapFilterChips({super.key, required this.chips, required this.onTap});

  final List<MapChipData> chips;
  final ValueChanged<String> onTap;

  @override
  State<MapFilterChips> createState() => _MapFilterChipsState();
}

class _MapFilterChipsState extends State<MapFilterChips> {
  final _scroll = ScrollController();
  bool _left = false, _right = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_edges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edges() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final l = p.pixels > 4, r = p.pixels < p.maxScrollExtent - 4;
    if (l != _left || r != _right) {
      setState(() {
        _left = l;
        _right = r;
      });
    }
  }

  @override
  void didUpdateWidget(MapFilterChips old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: [if (_left) const Color(0x00000000) else const Color(0xFF000000), const Color(0xFF000000), const Color(0xFF000000), if (_right) const Color(0x00000000) else const Color(0xFF000000)],
        stops: [0, _left ? 24 / r.width : 0.0001, 1 - (_right ? 28 / r.width : 0.0001), 1],
      ).createShader(r),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // the artifact's 12 px at the left, and room for a shadow above and below the chips
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          for (var i = 0; i < widget.chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            widget.chips[i].divider ? _Divider(d: d) : _Chip(data: widget.chips[i], onTap: () => widget.onTap(widget.chips[i].id)),
          ],
        ]),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.d});

  final DColors d;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 2), color: d.dark ? const Color(0xFF34383E) : const Color(0xFFD6DCEA));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.data, required this.onTap});

  final MapChipData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final sel = data.selected;
    final fill = sel ? (d.dark ? const Color(0xFF2457E6) : const Color(0xFF00308F)) : d.card;
    final ink = sel ? Colors.white : d.ink;
    final dotC = data.dot;
    final glyph = data.glyph;
    return Semantics(
      button: true,
      selected: sel,
      label: '${data.label}, ${data.count}',
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        // the chip is 40 high; the finger's area is 44
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(22), boxShadow: _lift(d, blur: 8)),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (dotC != null) ...[Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: dotC)), const SizedBox(width: 7)],
                      if (glyph != null) ...[MapGlyphIcon(glyph, size: 16, colour: sel ? Colors.white : const Color(0xFFCF4308)), const SizedBox(width: 7)],
                      Text(data.label, maxLines: 1, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, height: 1.1, color: ink)),
                      const SizedBox(width: 7),
                      Text('${data.count}',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, height: 1.1, color: sel ? Colors.white.withValues(alpha: .8) : d.muted)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- the buttons over the map -------------------------------------

/// A 48 px button over the map: the round Frame 183 (right), the rounded square Layers (left).
class MapFab extends StatelessWidget {
  const MapFab({super.key, required this.label, required this.glyph, required this.onTap, this.round = false, this.accent = false});

  final String label;
  final MapGlyph glyph;
  final VoidCallback onTap;
  final bool round;

  /// The icon in the navy (Frame 183) rather than the ink (Layers).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final shape = round ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: shape, shadows: _lift(d)),
        child: Material(
          color: d.card,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: SizedBox(width: 48, height: 48, child: Center(child: MapGlyphIcon(glyph, size: 22, colour: accent ? d.link : d.ink)))),
        ),
      ),
    );
  }
}

// ---------- the Layers sheet --------------------------------------------

/// One tile of the Layers sheet.
class MapLayerTile {
  const MapLayerTile({required this.id, required this.name, this.glyph, this.contrast = false});

  final String id;
  final String name;
  final MapGlyph? glyph;

  /// The Dim outside tile draws the artifact's half-filled circle.
  final bool contrast;
}

/// The Layers bottom sheet of the artifact: a title with a 44 px close, "MAP DETAILS", a tile per layer that is on or off,
/// and a line saying that the chips narrow it down. [isOn] and [toggle] are the screen's; the sheet redraws as they change.
Future<void> showMapLayersSheet(
  BuildContext context, {
  required List<MapLayerTile> tiles,
  required bool Function(String id) isOn,
  required void Function(String id) toggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.d.dark ? const Color(0x8C000000) : const Color(0x66141B34),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final d = ctx.d;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          decoration: BoxDecoration(
            color: d.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: d.dark ? const Color(0x80000000) : const Color(0x33141B34), blurRadius: 30, offset: const Offset(0, -8))],
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 28 + MediaQuery.paddingOf(ctx).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(ctx.tr('Layers', 'Mga layer'),
                        style: TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: 21, height: 28 / 21, letterSpacing: -.21, color: d.ink)),
                  ),
                ),
                Semantics(
                  button: true,
                  label: ctx.tr('Close', 'Isara'),
                  excludeSemantics: true,
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Material(
                    color: d.card,
                    shape: CircleBorder(side: BorderSide(color: d.line)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: SizedBox(width: 44, height: 44, child: Center(child: MapGlyphIcon(MapTabIcons.close, size: 20, colour: d.ink))),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(ctx.tr('MAP DETAILS', 'DETALYE NG MAPA'),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, height: 16 / 11.5, letterSpacing: 1.15, color: d.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 14, children: [
                for (final t in tiles)
                  _LayerTile(
                    tile: t,
                    on: isOn(t.id),
                    onTap: () {
                      toggle(t.id);
                      setSheet(() {});
                    },
                  ),
              ]),
              const SizedBox(height: 14),
              Text(ctx.tr('Layers choose what is drawn. The chips on the map narrow it down.', 'Ang mga layer ang pumipili ng ipinapakita. Ang mga chip sa mapa ang nagpapaliit nito.'),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 12.5, height: 18 / 12.5, color: d.muted)),
            ]),
          ),
        );
      },
    ),
  );
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({required this.tile, required this.on, required this.onTap});

  final MapLayerTile tile;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final fg = on ? d.link : d.ink2;
    return Semantics(
      toggled: on,
      label: tile.name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          // 84 wide; wider as the text grows, so a name is not broken in the middle of a word
          width: 84 * (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: on ? (d.dark ? const Color(0x2E8FADFF) : const Color(0x1400308F)) : (d.dark ? d.field : const Color(0xFFF4F6FB)),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? d.link : Colors.transparent, width: 2),
              ),
              child: Center(child: tile.contrast ? MapContrastIcon(colour: fg) : MapGlyphIcon(tile.glyph!, size: 26, colour: fg)),
            ),
            const SizedBox(height: 6),
            Text(tile.name,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 12, height: 15 / 12, color: fg)),
          ]),
        ),
      ),
    );
  }
}

// ---------- the progress track ------------------------------------------

/// How far a case has come, as the portal's track draws it: bars that are green (done), orange (now) or a line (to come),
/// or a red or grey stop where a case ended (rejected, cancelled, escalated out).
class MapTrackSpec {
  const MapTrackSpec({required this.done, this.now, this.stop, this.stopLabel, this.stopRed = true});

  /// How many of the four steps are done (0 to 4).
  final int done;

  /// The step in progress, or null (all done, or stopped).
  final int? now;

  /// The step where the case stopped, and what it says there.
  final int? stop;
  final String? stopLabel;
  final bool stopRed;
}

/// The progress track. With [labels] it is the artifact's Track (four steps named under their bars); without, the four
/// slim bars of the small card.
class MapTrack extends StatelessWidget {
  const MapTrack({super.key, required this.spec, required this.names, this.labels = true});

  final MapTrackSpec spec;
  final List<String> names;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final green = d.dark ? const Color(0xFF3FB868) : const Color(0xFF087F31);
    final line = d.dark ? const Color(0xFF34383E) : const Color(0xFFD6DCEA);
    final stopBar = spec.stopRed ? const Color(0xFFC4172A) : const Color(0xFF8A90A0);
    final stopInk = spec.stopRed ? (d.dark ? const Color(0xFFFF8A8A) : const Color(0xFFC4172A)) : d.muted;
    Color bar(int i) => spec.stop == i
        ? stopBar
        : i < spec.done
            ? const Color(0xFF087F31)
            : spec.now == i
                ? const Color(0xFFFF9800)
                : line;
    Color ink(int i) => spec.stop == i ? stopInk : spec.now == i ? d.ink : (i < spec.done ? green : d.muted);
    FontWeight weight(int i) => spec.stop == i || spec.now == i ? FontWeight.w800 : (i < spec.done ? FontWeight.w700 : FontWeight.w600);
    String text(int i) => spec.stop == i ? (spec.stopLabel ?? '') : names[i];
    bool tick(int i) => spec.stop != i && i < spec.done;
    TextStyle style(int i) => TextStyle(fontFamily: 'Inter', fontWeight: weight(i), fontSize: 11.5, height: 14 / 11.5, color: ink(i));

    // At a large text size four names do not fit side by side: the steps go one under another, each with its own bar.
    if (labels && MediaQuery.textScalerOf(context).scale(10) >= 13) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(width: 6, height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: bar(i))),
              const SizedBox(width: 12),
              if (tick(i)) ...[MapGlyphIcon(MapTabIcons.check, size: 14, colour: green, stroke: 2.4), const SizedBox(width: 4)],
              Expanded(child: Text(text(i), style: style(i))),
            ]),
          ),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 6, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: bar(i))),
            if (labels) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (tick(i)) ...[MapGlyphIcon(MapTabIcons.check, size: 12, colour: green, stroke: 2.4), const SizedBox(width: 3)],
                Expanded(child: Text(text(i), style: style(i))),
              ]),
            ],
          ]),
        ),
      ],
    ]);
  }
}

// ---------- the pin's card -----------------------------------------------

/// What a report's card says (both sizes).
class MapCardData {
  const MapCardData({
    required this.colour,
    required this.glyph,
    required this.category,
    required this.title,
    required this.place,
    required this.statusLabel,
    required this.statusColour,
    required this.track,
    required this.names,
    this.ticket,
    this.placeSub,
    this.concerns,
    this.updated,
    this.note,
  });

  final Color colour;

  /// The complaint type's icon key (map_glyphs.dart).
  final String glyph;
  final String category;
  final String title;
  final String? ticket;
  final String place;
  final String? placeSub;
  final String statusLabel;
  final Color statusColour;

  /// "3 concerns · 1 resolved", when there are several.
  final String? concerns;
  final MapTrackSpec track;
  final List<String> names;

  /// "Tanod dispatched · updated 2 hours ago".
  final String? updated;

  /// A line in place of the track and the button (a published incident of someone else's).
  final String? note;
}

class _ConcernsTag extends StatelessWidget {
  const _ConcernsTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x80788096))),
      child: Text(text, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, height: 1.1, color: d.ink2)),
    );
  }
}

/// The small card a pin opens (the artifact's pin card): a handle, a header in the category colour with the status pill,
/// the title, the ticket and place, "3 concerns · 1 resolved", the four bars, when it was last updated, and Open this
/// report. A tap anywhere opens the report; the handle, or a drag up, expands it into [MapBigCard].
class MapPeekCard extends StatelessWidget {
  const MapPeekCard({super.key, required this.data, required this.onOpen, required this.onExpand, required this.onClose});

  final MapCardData data;
  final VoidCallback onOpen;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final disc = concernFill(data.colour);
    final tint = data.colour.withValues(alpha: d.dark ? .20 : .10);
    final open = data.note == null;
    final summary = [data.category, data.title, data.statusLabel, if (data.concerns != null) data.concerns!].join(', ');
    return Semantics(
      container: true,
      label: summary,
      customSemanticsActions: {
        CustomSemanticsAction(label: context.tr('Expand', 'Palakihin')): onExpand,
        CustomSemanticsAction(label: context.tr('Close', 'Isara')): onClose,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open ? onOpen : null,
        child: Container(
          decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(22), boxShadow: _lift(d, blur: 18, dy: 4)),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                // the drag handle, and the header, answer a drag up
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (e) {
                    final v = e.primaryVelocity ?? 0;
                    if (v < -150) onExpand();
                    if (v > 150) onClose();
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
                          child: Center(child: MapGlyphIcon(categoryMapGlyph(data.glyph), size: 18, colour: Colors.white, stroke: 2.2)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(data.category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13, height: 18 / 13, color: d.ink)),
                        ),
                        const SizedBox(width: 10),
                        DStatusPill(data.statusLabel, data.statusColour),
                      ]),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 8),
                    Text(data.title,
                        style: TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: 20, height: 26 / 20, letterSpacing: -.2, color: d.ink)),
                    const SizedBox(height: 2),
                    _TicketLine(data: data, size: 13),
                    if (data.concerns != null) ...[const SizedBox(height: 6), _ConcernsTag(data.concerns!)],
                    if (open) ...[
                      const SizedBox(height: 12),
                      MapTrack(spec: data.track, names: data.names, labels: false),
                      if (data.updated != null) ...[
                        const SizedBox(height: 6),
                        Text(data.updated!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 12, height: 16 / 12, color: d.muted)),
                      ],
                      const SizedBox(height: 12),
                      DFormButton(context.tr('Open this report', 'Buksan ang report'), small: true, onTap: onOpen),
                    ] else if (data.note != null) ...[
                      const SizedBox(height: 10),
                      Text(data.note!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13, height: 1.4, color: d.muted)),
                    ],
                  ]),
                ),
              ]),
            ),
            // the handle: a 4 px bar the finger reaches within 44 px
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 44,
              child: Semantics(
                button: true,
                label: context.tr('Expand the card', 'Palakihin ang card'),
                excludeSemantics: true,
                onTap: onExpand,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onExpand,
                  onVerticalDragEnd: (e) {
                    final v = e.primaryVelocity ?? 0;
                    if (v < -150) onExpand();
                    if (v > 150) onClose();
                  },
                  child: Align(
                    alignment: const Alignment(0, -.55),
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TicketLine extends StatelessWidget {
  const _TicketLine({required this.data, required this.size});

  final MapCardData data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Text.rich(
      TextSpan(children: [
        if (data.ticket != null && data.ticket!.isNotEmpty) ...[
          TextSpan(text: data.ticket, style: TextStyle(fontWeight: FontWeight.w800, color: d.link)),
          const TextSpan(text: ' · '),
        ],
        TextSpan(text: data.place),
      ]),
      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: size, height: 18 / 13, color: d.muted),
    );
  }
}

/// The card the small one expands into: the portal's case card. A hero in the category colour (grip, a 44 px close, the
/// symbol large, the category's name), the title, the ticket with the status pill and the concerns, the place, the track
/// with its steps named, and Open this report.
class MapBigCard extends StatelessWidget {
  const MapBigCard({super.key, required this.data, required this.onOpen, required this.onCollapse, required this.onClose});

  final MapCardData data;
  final VoidCallback onOpen;
  final VoidCallback onCollapse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final hsl = HSLColor.fromColor(concernFill(data.colour));
    final from = hsl.toColor();
    final to = hsl.withLightness((hsl.lightness - .14).clamp(0.08, 1.0)).toColor();
    final open = data.note == null;
    return Semantics(
      container: true,
      label: [data.category, data.title, data.statusLabel, if (data.concerns != null) data.concerns!].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open ? onOpen : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: d.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: d.dark ? const Color(0x80000000) : const Color(0x33141B34), blurRadius: 30, offset: const Offset(0, -8))],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Material(
              type: MaterialType.transparency,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // the hero: a drag down hands back the small card
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (e) {
                  if ((e.primaryVelocity ?? 0) > 150) onCollapse();
                },
                child: Container(
                  height: 130 + 30 * ((MediaQuery.textScalerOf(context).scale(10) / 10 - 1).clamp(0.0, 1.0)),
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to])),
                  child: Stack(children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: Semantics(
                        button: true,
                        label: context.tr('Make the card smaller', 'Paliitin ang card'),
                        excludeSemantics: true,
                        onTap: onCollapse,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onCollapse,
                          child: Align(
                            alignment: const Alignment(0, -.55),
                            child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(2))),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: Semantics(
                        button: true,
                        label: context.tr('Close', 'Isara'),
                        excludeSemantics: true,
                        onTap: onClose,
                        child: Material(
                          color: const Color(0x47000000),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(onTap: onClose, child: SizedBox(width: 44, height: 44, child: Center(child: MapGlyphIcon(MapTabIcons.close, size: 20, colour: Colors.white)))),
                        ),
                      ),
                    ),
                    Center(child: MapGlyphIcon(categoryMapGlyph(data.glyph), size: 56, colour: Colors.white.withValues(alpha: .95), stroke: 1.8)),
                    Positioned(
                      left: 14,
                      bottom: 12,
                      right: 14,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 28),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(14)),
                          child: Text(data.category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.1, color: Colors.white)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(data.title,
                        style: TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: 22, height: 28 / 22, letterSpacing: -.22, color: d.ink)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (data.ticket != null && data.ticket!.isNotEmpty)
                        Text(data.ticket!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14, height: 20 / 14, color: d.link)),
                      Row(mainAxisSize: MainAxisSize.min, children: [DStatusPill(data.statusLabel, data.statusColour)]),
                      if (data.concerns != null) _ConcernsTag(data.concerns!),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: d.line))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 1), child: MapGlyphIcon(MapTabIcons.pin, size: 22, colour: d.link)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(data.place, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14.5, height: 20 / 14.5, color: d.ink)),
                            if (data.placeSub != null)
                              Text(data.placeSub!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 12.5, height: 17 / 12.5, color: d.muted)),
                          ]),
                        ),
                      ]),
                    ),
                    if (open)
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: d.line))),
                        child: MapTrack(spec: data.track, names: data.names),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: d.line))),
                        child: Text(data.note!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13, height: 1.4, color: d.muted)),
                      ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),
              if (open)
                Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 9 + math.max(MediaQuery.paddingOf(context).bottom, 6)),
                  child: DFormButton(context.tr('Open this report', 'Buksan ang report'), onTap: onOpen),
                )
              else
                SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- notes the tab says when there is nothing to draw ----------------

/// A card at the foot of the map for a state: loading, no reports yet, a filter with no results, reports that could not be
/// read. One line of words, a second under it, and at most one button.
class MapNote extends StatelessWidget {
  const MapNote({super.key, required this.title, this.body, this.action, this.onAction, this.busy = false, this.primary = false});

  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  /// A spinner in place of the words' icon (loading).
  final bool busy;

  /// The one orange action of the screen (when nothing else is).
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      container: true,
      liveRegion: busy,
      label: [title, ?body].join('. '),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(22), boxShadow: _lift(d, blur: 18, dy: 4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (busy) ...[
              const Padding(padding: EdgeInsets.only(top: 2), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(child: Text(title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, height: 20 / 15, color: d.ink))),
                if (body != null)
                  ExcludeSemantics(child: Text(body!, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13, height: 18 / 13, color: d.muted))),
              ]),
            ),
          ]),
          if (action != null) ...[
            const SizedBox(height: 10),
            DFormButton(action!, small: true, kind: primary ? DFormKind.primary : DFormKind.ghost, onTap: onAction),
          ],
        ]),
      ),
    );
  }
}
