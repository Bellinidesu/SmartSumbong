// SmartSumbong — a pin's card, in the portal's case-sheet style.
//
// The portal opens a pressed pin as a Google Maps-style panel (spatial.js
// showDetail, flair-map.css .cs-*): a hero in the complaint type's colour
// with a grip, a close button, the type's chip and its symbol large in the
// middle; the subject; the ticket and a status dot; rows with an outline
// icon each; Progress as four coloured bubbles joined by a bar; and the
// orange button at the foot. On the phone it rises from the bottom (a
// sheet), with the same parts. What it says is the screen's: this widget
// only lays it out.

import 'package:flutter/material.dart';

import '../d/d_ui.dart';
import 'brgy_map.dart' show BrgyMapSkin;
import 'map_glyphs.dart';

/// One row of the card (.cs-rows li): an icon, a line, a second line.
class BrgyMapCardRow {
  const BrgyMapCardRow({required this.glyph, required this.title, this.sub});

  final MapGlyph glyph;
  final String title;
  final String? sub;
}

class BrgyMapCaseCard extends StatelessWidget {
  const BrgyMapCaseCard({
    super.key,
    required this.colour,
    required this.glyph,
    required this.category,
    required this.title,
    required this.statusLabel,
    required this.statusColour,
    this.ticket,
    this.rows = const [],
    this.steps = const [],
    this.stepsOn = 0,
    this.note,
    this.action,
    this.onAction,
    this.onClose,
  });

  final Color colour;

  /// The complaint type's icon key (map_glyphs.dart).
  final String glyph;
  final String category;
  final String title;
  final String statusLabel;
  final Color statusColour;

  /// The tracking ID, for the resident's own reports.
  final String? ticket;
  final List<BrgyMapCardRow> rows;

  /// Progress: the stage names, and how many are reached.
  final List<String> steps;
  final int stepsOn;

  /// A line in place of the button (a published incident).
  final String? note;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  /// The portal's one colour code for progress (spatial.js STAGE_COL,
  /// brighter at night): filed grey, validated amber, dispatched blue,
  /// resolved green.
  static List<Color> stageColours(bool dark) => dark
      ? const [Color(0xFFB4BCCB), Color(0xFFFFB61F), Color(0xFF3D7BFF), Color(0xFF2FDC74)]
      : const [Color(0xFF9AA3B2), Color(0xFFF9AB00), Color(0xFF2F6BFF), Color(0xFF1E9E56)];

  static const _stageGlyphs = [MapIcons.photo, MapIcons.handler, MapIcons.send, MapIcons.safepoints];

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Hero(colour: colour, glyph: glyph, category: category, onClose: onClose),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: 21, height: 1.25, color: k.ink)),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              if (ticket != null && ticket!.isNotEmpty) ...[
                TextSpan(text: ticket, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13.5, color: k.link)),
                TextSpan(text: ' · ', style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: k.muted)),
              ],
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: statusColour)),
              ),
              TextSpan(text: statusLabel, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13.5, color: k.ink)),
            ])),
            if (rows.isNotEmpty) const SizedBox(height: 6),
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: MapGlyphIcon(r.glyph, size: 20, colour: k.link, stroke: 1.8)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 14, height: 1.3, color: k.ink)),
                      if (r.sub != null) ...[
                        const SizedBox(height: 2),
                        Text(r.sub!, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, height: 1.3, color: k.muted)),
                      ],
                    ]),
                  ),
                ]),
              ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(context.tr('PROGRESS', 'TAKBO'),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.1, color: k.muted)),
              const SizedBox(height: 10),
              _Stages(labels: steps, on: stepsOn, last: statusColour),
            ],
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(note!, style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.4, color: k.muted)),
            ],
          ]),
        ),
      ),
      if (action != null)
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
          child: DButton(action!, expand: true, onTap: onAction),
        )
      else
        const SizedBox(height: 10),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.colour, required this.glyph, required this.category, this.onClose});

  final Color colour;
  final String glyph;
  final String category;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    // .cs-hero: a radial wash of the colour by day (solid in Material), the
    // colour fading into the card at night
    final deco = k.dark
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.alphaBlend(colour.withValues(alpha: .62), k.surface(3)), Color.alphaBlend(colour.withValues(alpha: .12), k.surface(3))],
            ),
          )
        : BoxDecoration(color: colour);
    return SizedBox(
      height: 132,
      child: DecoratedBox(
        decoration: deco,
        child: Stack(children: [
          // the grip
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(4)))),
          ),
          Center(child: MapGlyphIcon(categoryMapGlyph(glyph), size: 60, colour: Colors.white.withValues(alpha: .92), stroke: 1.8)),
          Positioned(
            left: 16,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), borderRadius: BorderRadius.circular(99)),
              child: Text(category, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: .4, color: Colors.white)),
            ),
          ),
          if (onClose != null)
            Positioned(
              top: 10,
              right: 10,
              child: Semantics(
                button: true,
                label: context.tr('Close', 'Isara'),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), shape: BoxShape.circle),
                    child: const Center(child: MapGlyphIcon(MapIcons.close, size: 18, colour: Colors.white, stroke: 2.4)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// .cs-stg: a bubble per stage, joined by a bar that lights in the two
/// stages' colours as the case moves on; the stage it is at is a little
/// larger, ringed, its name in its colour.
class _Stages extends StatelessWidget {
  const _Stages({required this.labels, required this.on, required this.last});

  final List<String> labels;
  final int on;

  /// The last stage's colour when the path is short (rejected, escalated).
  final Color last;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    final full = labels.length == 4;
    final cols = BrgyMapCaseCard.stageColours(k.dark);
    Color col(int i) => full ? cols[i] : (i == 0 ? cols[0] : last);
    MapGlyph g(int i) => full ? BrgyMapCaseCard._stageGlyphs[i] : (i == 0 ? MapIcons.photo : MapIcons.handler);
    final cur = (on - 1).clamp(0, labels.length - 1);
    final off = k.dark ? const Color(0xFF1A1C24) : const Color(0xFFF1F3F8);
    final offEdge = k.dark ? Colors.white.withValues(alpha: .22) : const Color(0x33141B34);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth / labels.length;
      return Stack(children: [
        // the bars between bubbles
        for (var i = 0; i < labels.length - 1; i++)
          Positioned(
            left: w * i + w / 2,
            width: w,
            top: 17,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i < cur ? null : (k.dark ? Colors.white.withValues(alpha: .14) : offEdge),
                gradient: i < cur ? LinearGradient(colors: [col(i), col(i + 1)]) : null,
              ),
            ),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < labels.length; i++)
            SizedBox(
              width: w,
              child: Column(children: [
                Transform.scale(
                  scale: i == cur ? 1.14 : 1,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < on ? col(i) : off,
                      border: Border.all(color: i < on ? col(i) : offEdge, width: 2),
                      boxShadow: i == cur ? [BoxShadow(color: col(i).withValues(alpha: .28), spreadRadius: 5)] : null,
                    ),
                    child: Center(
                      child: MapGlyphIcon(i < cur ? MapIcons.check : g(i),
                          size: 18, colour: i < on ? Colors.white : k.muted, stroke: i < cur ? 3 : 2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: i < on ? FontWeight.w700 : FontWeight.w500,
                      color: i == cur ? col(i) : (i < on ? k.ink : k.muted),
                    )),
              ]),
            ),
        ]),
      ]);
    });
  }
}
