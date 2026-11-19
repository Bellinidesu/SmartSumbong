// SmartSumbong: the case screen's parts (19 Nov 2026, Ace's "case page now").
//
// Built 1:1 from the approved design canvas ("Report Flow and Case Screen", frames S-Review, S-Progress, S-Rejected,
// S-Cancelled, S-More, S-Reopen, R1, TL1, EV1, EV2, N1-N5, L1 and their shared parts: CaseHero, Pill, Track, Button,
// ActionBar, Strip, Evidence, ResolvedCard, Completed, StatusCase). One piece per component, so the screen reads as the
// canvas does. The canvas' colours are used as drawn (its tokens are in [CaseTokens]).

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:latlong2/latlong.dart' as ll;
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../../i18n.dart';
import '../../widgets/brgy_map.dart';

// ---------- tokens --------------------------------------------

/// The canvas' colours for one mode (light, or the portal's graphite at night).
class CaseTokens {
  const CaseTokens._({
    required this.dark,
    required this.bg,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.edge,
    required this.navy,
    required this.shadow,
    required this.field,
    required this.green,
  });

  final bool dark;
  final Color bg;
  final Color card;
  final Color ink;
  final Color ink2;
  final Color muted;

  /// A card's own edge.
  final Color line;

  /// The stronger line: a button's edge, a track's empty bar, a radio's ring.
  final Color edge;
  final Color navy;
  final Color shadow;
  final Color field;

  /// Green lettering on a card (the done steps).
  final Color green;

  static const light = CaseTokens._(
    dark: false,
    bg: Color(0xFFEEF2FA),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF141B34),
    ink2: Color(0xFF3A4058),
    muted: Color(0xFF5F6673),
    line: Color(0xFFE3E8F3),
    edge: Color(0xFFD6DCEA),
    navy: Color(0xFF00308F),
    shadow: Color(0x2420273B),
    field: Color(0xFFF4F6FB),
    green: Color(0xFF066A27), // darker than the done fill: it keeps 4.5:1 as lettering on the Resolved card's green tint
  );

  static const night = CaseTokens._(
    dark: true,
    bg: Color(0xFF101215),
    card: Color(0xFF17191D),
    ink: Color(0xFFF3F3F3),
    ink2: Color(0xFFC9CCD1),
    muted: Color(0xFFA8A8A8),
    line: Color(0xFF2A2D33),
    edge: Color(0xFF34383E),
    navy: Color(0xFF8FADFF),
    shadow: Color(0x73000000),
    field: Color(0xFF1D2025),
    green: Color(0xFF3FB868),
  );

  static CaseTokens of(BuildContext context) => context.d.dark ? night : light;

  /// The solid green of a done step, a Resolved tick, a Proof tag.
  static const doneFill = Color(0xFF087F31);
  static const orange = Color(0xFFFF9800);

  /// "Appeal this decision": its own red (not the status red, not the category red).
  static const appealRed = Color(0xFFD64040);

  /// Text on a red or tinted danger surface.
  Color get dangerInk => dark ? const Color(0xFFFF8A8A) : const Color(0xFFC4172A);
}

TextStyle caseInter(Color c, double size, FontWeight w, [double? line]) =>
    TextStyle(fontFamily: 'Inter', fontWeight: w, fontSize: size, height: line == null ? null : line / size, color: c);

TextStyle caseTight(Color c, double size, [double? line]) => TextStyle(
    fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: size, height: line == null ? null : line / size, letterSpacing: -.01 * size, color: c);

/// A card of the canvas: white (graphite at night), a 1 px edge, radius 20 and a soft shadow.
BoxDecoration caseCardBox(CaseTokens t, {double radius = 20}) => BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: t.line),
      boxShadow: [BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 2))],
    );

// ---------- media ---------------------------------------------

/// One photo or video of a case, for the thumbnails and the viewer.
class CaseMedia {
  const CaseMedia({required this.url, this.isVideo = false, this.fromBarangay = false, this.at, this.title, this.text});

  final String url;
  final bool isVideo;

  /// The barangay's proof or update; false is the resident's own photo.
  final bool fromBarangay;
  final DateTime? at;

  /// The viewer's caption: a headline and the words under the date.
  final String? title;
  final String? text;
}

/// A picture the canvas draws as a soft gradient while it loads (and where the network has nothing).
class CaseThumb extends StatelessWidget {
  const CaseThumb({super.key, required this.media, required this.semantics, this.onTap, this.size = 56, this.tag});

  final CaseMedia media;
  final String semantics;
  final VoidCallback? onTap;
  final double size;

  /// "Proof": the green tag over a barangay photo.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final g = media.fromBarangay
        ? (t.dark ? const [Color(0xFF3B5A47), Color(0xFF223328)] : const [Color(0xFF8FC1A2), Color(0xFFD2EBDA)])
        : (t.dark ? const [Color(0xFF4A5266), Color(0xFF2B3140)] : const [Color(0xFF9AA6BD), Color(0xFFD3DAE8)]);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g)),
    );
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(size > 80 ? 16 : 12),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          placeholder,
          if (!media.isVideo)
            CachedNetworkImage(
              imageUrl: cloudinarySized(media.url, width: size > 80 ? 800 : 160),
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => Icon(Icons.image_outlined, size: size * .4, color: Colors.white.withValues(alpha: .55)),
            ),
          if (media.isVideo)
            Center(
              child: Container(
                width: size * .5,
                height: size * .5,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, size: size * .34, color: Colors.white),
              ),
            ),
          if (tag != null)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: CaseTokens.doneFill, borderRadius: BorderRadius.circular(8)),
                child: Text(tag!, textScaler: TextScaler.noScaling, style: caseInter(Colors.white, 10, FontWeight.w800, 16)),
              ),
            ),
        ]),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: semantics,
      child: ExcludeSemantics(
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: thumb),
      ),
    );
  }
}

// ---------- header --------------------------------------------

/// CaseHero: the thin header, the category's colour with back, the category's name and share.
class CaseHeader extends StatelessWidget {
  const CaseHeader({super.key, required this.colour, required this.onBack, this.glyph, this.onShare});

  final Color colour;
  /// The category's own symbol (as its map pin wears it), drawn large and faint behind the buttons, bleeding off the edge.
  final IconData? glyph;
  final VoidCallback onBack;
  final VoidCallback? onShare;

  /// The header's height under a status bar of [top]: the canvas' 104 on a 44 px bar.
  static double heightFor(double top) => math.max(top, 44.0) + 60;

  @override
  Widget build(BuildContext context) {
    final top = math.max(MediaQuery.paddingOf(context).top, 44.0);
    Widget round(IconData icon, String name, VoidCallback onTap, double size) => Semantics(
          button: true,
          label: name,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .28), shape: BoxShape.circle),
                child: Icon(icon, size: size, color: Colors.white),
              ),
            ),
          ),
        );
    return Container(
      height: top + 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colour, Color.lerp(colour, Colors.black, .42)!]),
      ),
      child: Stack(children: [
        if (glyph != null)
          Positioned(
            right: -22,
            top: -30,
            child: IgnorePointer(child: ExcludeSemantics(child: Icon(glyph, size: 190, color: Colors.white.withValues(alpha: .15)))),
          ),
        Positioned(left: 18, top: top + 8, child: round(Icons.chevron_left_rounded, context.tr('Back', 'Bumalik'), onBack, 28)),
        if (onShare != null) Positioned(right: 18, top: top + 8, child: round(Icons.ios_share_rounded, context.tr('Share this report', 'Ibahagi ang ulat'), onShare!, 20)),
      ]),
    );
  }
}

// ---------- the title block -----------------------------------

/// Title, ticket, status pill, filed date and the one sentence that says where the report is.
class CaseTitleBlock extends StatelessWidget {
  const CaseTitleBlock({
    super.key,
    required this.title,
    required this.ticket,
    required this.pillLabel,
    required this.pillColour,
    required this.filed,
    required this.answer,
    this.extraLine,
    this.extraColour,
  });

  final String title;
  final String ticket;
  final String pillLabel;
  final Color pillColour;
  final String filed;
  final String answer;

  /// "Escalated to the Chairman", "Reopened once": one quiet line under the sentence.
  final String? extraLine;
  final Color? extraColour;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(title, style: caseTight(t.ink, 26, 32))),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(ticket, style: caseInter(t.navy, 14, FontWeight.w800, 20)),
        DStatusPill(pillLabel, pillColour),
        Text(filed, style: caseInter(t.muted, 13, FontWeight.w500, 18)),
      ]),
      const SizedBox(height: 10),
      Text(answer, style: caseInter(t.ink, 15, FontWeight.w600, 22)),
      if (extraLine != null) ...[
        const SizedBox(height: 4),
        Text(extraLine!, style: caseInter(extraColour ?? t.muted, 13, FontWeight.w700, 18)),
      ],
    ]);
  }
}

// ---------- the portal's track ---------------------------------

/// Track: four steps, green when done, orange for where the report is, grey for what is left. Drawn only while the report moves.
class CaseTrack extends StatelessWidget {
  const CaseTrack({super.key, required this.done});

  /// How many steps are done (0-4). The next one is "now".
  final int done;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final names = [
      context.tr('Filed', 'Naisampa'),
      context.tr('Validated', 'Napatunayan'),
      context.tr('Tanod dispatched', 'Na-dispatch ang tanod'),
      context.tr('Resolved', 'Nalutas'),
    ];
    final now = done.clamp(0, 4);
    // At a large text size four labels cannot sit under four bars without breaking words, so the bars stay in one row and the
    // labels become a list under them, one step to a line.
    final large = MediaQuery.textScalerOf(context).scale(11.5) / 11.5 >= 1.2;
    if (large) {
      return Semantics(
        container: true,
        label: now >= 4
            ? context.tr('Progress: all four steps done', 'Progreso: tapos na ang apat na hakbang')
            : context.tr('Progress: $now of 4 steps done, now ${names[now]}', 'Progreso: $now sa 4 na hakbang ang tapos, ngayon ${names[now]}'),
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: Container(height: 6, decoration: BoxDecoration(color: i < now ? CaseTokens.doneFill : (i == now ? CaseTokens.orange : t.edge), borderRadius: BorderRadius.circular(3)))),
              ],
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 18, child: i < now ? Icon(Icons.check_rounded, size: 14, color: t.green) : Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 8, height: 8, margin: const EdgeInsets.only(left: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: i == now ? CaseTokens.orange : t.edge)))),
                  Expanded(child: Text(names[i], style: caseInter(i < now ? t.green : (i == now ? t.ink : t.muted), 11.5, i == now ? FontWeight.w800 : (i < now ? FontWeight.w700 : FontWeight.w600), 14).copyWith(height: 1.3))),
                ]),
              ),
          ]),
        ),
      );
    }
    return Semantics(
      container: true,
      label: now >= 4
          ? context.tr('Progress: all four steps done', 'Progreso: tapos na ang apat na hakbang')
          : context.tr('Progress: $now of 4 steps done, now ${names[now]}', 'Progreso: $now sa 4 na hakbang ang tapos, ngayon ${names[now]}'),
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i < now ? CaseTokens.doneFill : (i == now ? CaseTokens.orange : t.edge),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (i < now) Padding(padding: const EdgeInsets.only(top: 1, right: 2), child: Icon(Icons.check_rounded, size: 12, color: t.green)),
                  Flexible(
                    child: Text(names[i],
                        style: caseInter(i < now ? t.green : (i == now ? t.ink : t.muted), 11.5, i == now ? FontWeight.w800 : (i < now ? FontWeight.w700 : FontWeight.w600), 14)),
                  ),
                ]),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ---------- notes ---------------------------------------------

/// A tinted note: a dot in the tone's colour, an optional bold title, the words, and at most one underlined action.
class CaseNote extends StatelessWidget {
  const CaseNote({super.key, required this.tone, required this.body, this.title, this.action, this.foot});

  final Color tone;
  final String? title;
  final String body;
  final (String, VoidCallback)? action;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.withValues(alpha: t.dark ? .18 : .10), t.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: .45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(shape: BoxShape.circle, color: tone)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title!, style: caseInter(t.ink, 14, FontWeight.w800, 20)),
            Padding(
              padding: EdgeInsets.only(top: title != null ? 2 : 0),
              child: Text(body, style: caseInter(t.ink2, 13.5, FontWeight.w500).copyWith(height: 1.45)),
            ),
            if (action != null)
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: action!.$2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(action!.$1, style: caseInter(t.navy, 13.5, FontWeight.w800).copyWith(decoration: TextDecoration.underline)),
                    ),
                  ),
                ),
              ),
            if (foot != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(foot!, style: caseInter(t.muted, 12, FontWeight.w500, 16))),
          ]),
        ),
      ]),
    );
  }
}

// ---------- concerns ------------------------------------------

enum CaseConcernState { open, handled, resolved }

class CaseConcern {
  const CaseConcern({required this.name, required this.sub, required this.state, this.filedAs});

  final String name;
  final String sub;
  final CaseConcernState state;

  /// "Filed as ..." when the category was renamed since (0163).
  final String? filedAs;
}

/// Your concerns: each with its own status. Drawn only when there are two or more.
class CaseConcernsCard extends StatelessWidget {
  const CaseConcernsCard({super.key, required this.concerns, required this.dot});

  final List<CaseConcern> concerns;

  /// The category's colour, the dot before each name.
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final done = concerns.where((c) => c.state == CaseConcernState.resolved).length;
    (String, Color) pill(CaseConcernState st) => switch (st) {
          CaseConcernState.open => (context.tr('Open', 'Bukas'), DStatusPill.open),
          CaseConcernState.handled => (context.tr('Being handled', 'Inaasikaso'), DStatusPill.progress),
          CaseConcernState.resolved => (context.tr('Resolved', 'Nalutas'), DStatusPill.done),
        };
    return Container(
      decoration: caseCardBox(t),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Semantics(header: true, child: Text(context.tr('Your concerns', 'Mga concern mo'), style: caseInter(t.ink, 15, FontWeight.w800, 20))),
            Text(context.tr('$done of ${concerns.length} resolved', '$done sa ${concerns.length} ang nalutas'), style: caseInter(t.muted, 12.5, FontWeight.w600, 18)),
          ]),
        ),
        for (var i = 0; i < concerns.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: t.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(concerns[i].name, style: caseInter(t.ink, 14, FontWeight.w800, 19)),
                  Text(concerns[i].sub, style: caseInter(t.muted, 12.5, FontWeight.w500, 17)),
                  if (concerns[i].filedAs != null) Text(concerns[i].filedAs!, style: caseInter(t.muted, 12, FontWeight.w500, 16)),
                ]),
              ),
              const SizedBox(width: 12),
              Builder(builder: (_) {
                final p = pill(concerns[i].state);
                return DStatusPill(p.$1, p.$2);
              }),
            ]),
          ),
      ]),
    );
  }
}

// ---------- evidence ------------------------------------------

/// Evidence: your photos on the left, the barangay's proof on the right with a green Proof tag; tap any thumbnail for the viewer.
class CaseEvidenceCard extends StatelessWidget {
  const CaseEvidenceCard({super.key, required this.mine, required this.barangay, required this.onOpen, this.onAdd, this.barangayBase});

  final List<CaseMedia> mine;
  final List<CaseMedia> barangay;

  /// Opens the viewer at an index into mine + barangay (mine first).
  final void Function(int index) onOpen;

  /// The Add tile, while the barangay asked for more details.
  final VoidCallback? onAdd;

  /// Where the barangay's thumbnails start in the viewer's list, when it is not right after yours.
  final int? barangayBase;

  static const _cap = 3;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final total = mine.length + barangay.length;

    Widget more(int extra, int from) => Semantics(
          button: true,
          label: context.tr('$extra more, open the viewer', '$extra pa, buksan ang viewer'),
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(from),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.edge)),
                child: Text('+$extra', style: caseInter(t.ink2, 14, FontWeight.w800)),
              ),
            ),
          ),
        );

    List<Widget> thumbs(List<CaseMedia> list, int offset, {bool proof = false}) {
      final shown = math.min(list.length, _cap);
      return [
        for (var i = 0; i < shown; i++)
          CaseThumb(
            media: list[i],
            tag: proof ? context.tr('Proof', 'Patunay') : null,
            semantics: proof
                ? context.tr('Barangay proof ${i + 1} of ${list.length}', 'Patunay ng barangay ${i + 1} sa ${list.length}')
                : context.tr('Your photo ${i + 1} of ${list.length}', 'Larawan mo ${i + 1} sa ${list.length}'),
            onTap: () => onOpen(offset + i),
          ),
        if (list.length > _cap) more(list.length - _cap, offset + _cap),
      ];
    }

    Widget group(String label, List<Widget> kids) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: caseInter(t.muted, 12, FontWeight.w700, 16)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: kids),
        ]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: caseCardBox(t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Semantics(header: true, child: Text(context.tr('Evidence', 'Ebidensya'), style: caseInter(t.ink, 15, FontWeight.w800, 20)))),
          if (total > 0)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onOpen(0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                  child: Align(alignment: Alignment.centerRight, child: Text(context.tr('View all', 'Tingnan lahat'), style: caseInter(t.navy, 13, FontWeight.w800))),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 2),
        Wrap(spacing: 18, runSpacing: 12, children: [
          if (mine.isNotEmpty || onAdd != null)
            group(context.tr('Your photos · ${mine.length}', 'Mga larawan mo · ${mine.length}'), [
              ...thumbs(mine, 0),
              if (onAdd != null)
                Semantics(
                  button: true,
                  label: context.tr('Add photos', 'Magdagdag ng larawan'),
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAdd,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: t.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.edge, width: 1.5)),
                        child: Icon(Icons.add_rounded, size: 22, color: t.ink),
                      ),
                    ),
                  ),
                ),
            ]),
          if (barangay.isNotEmpty) group(context.tr('From the barangay · ${barangay.length}', 'Mula sa barangay · ${barangay.length}'), thumbs(barangay, barangayBase ?? mine.length, proof: true)),
        ]),
      ]),
    );
  }
}

// ---------- the details card ----------------------------------

class CaseDetailRow {
  const CaseDetailRow(this.icon, this.title, [this.sub]);

  final IconData icon;
  final String title;
  final String? sub;
}

/// The folded details: the place on top, a fold that opens your words, the place, the date and who is handling it.
class CaseDetailsCard extends StatefulWidget {
  const CaseDetailsCard({super.key, this.address, this.addressSub, this.quote, required this.rows, required this.foldLabel, this.extra = const []});

  final String? address;
  final String? addressSub;

  /// What the resident wrote.
  final String? quote;

  /// The rows shown open: the place, the date, the tanod.
  final List<CaseDetailRow> rows;

  /// Anything more the report has (the official, the target date, anonymous, SMART's reason): shown open, under the rows.
  final List<Widget> extra;
  final String foldLabel;

  @override
  State<CaseDetailsCard> createState() => _CaseDetailsCardState();
}

class _CaseDetailsCardState extends State<CaseDetailsCard> {
  bool _open = false;

  Widget _row(CaseTokens t, CaseDetailRow r, {bool first = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: t.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(r.icon, size: 22, color: t.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: caseInter(t.ink, 14.5, FontWeight.w700, 20)),
              if (r.sub != null) Text(r.sub!, style: caseInter(t.muted, 12.5, FontWeight.w500, 17)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final hasAddress = widget.address != null;
    final fold = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: (hasAddress || _open) ? Border(top: BorderSide(color: t.line)) : null),
          child: Row(children: [
            Expanded(child: Text(_open ? context.tr('Hide details', 'Itago ang detalye') : widget.foldLabel, style: caseInter(t.ink2, 14, FontWeight.w700))),
            Icon(Icons.expand_more_rounded, size: 20, color: t.muted).rotated(_open ? 180 : 0),
          ]),
        ),
      ),
    );
    return Container(
      decoration: caseCardBox(t),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_open && hasAddress) _row(t, CaseDetailRow(Icons.place_outlined, widget.address!, widget.addressSub), first: true),
        if (_open) ...[
          if (widget.quote != null && widget.quote!.trim().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text('“${widget.quote!.trim()}”', style: caseInter(t.ink2, 14, FontWeight.w500).copyWith(height: 1.5))),
          for (var i = 0; i < widget.rows.length; i++) _row(t, widget.rows[i], first: false),
          ...widget.extra,
        ],
        fold,
      ]),
    );
  }
}

extension _Rot on Widget {
  Widget rotated(double deg) => Transform.rotate(angle: deg * math.pi / 180, child: this);
}

/// A card-sized fold that opens another page (Full timeline).
class CaseFold extends StatelessWidget {
  const CaseFold({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    return Semantics(
      button: true,
      child: Material(
        color: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: t.line)),
        elevation: 0,
        shadowColor: t.shadow,
        child: Ink(
          decoration: caseCardBox(t),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(icon, size: 22, color: t.navy),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: caseInter(t.ink, 15, FontWeight.w800, 20))),
                Icon(Icons.chevron_right_rounded, size: 20, color: t.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- the Resolved card ---------------------------------

/// One step of "How it was handled". [note] and [thumb] are for the tanod's shared steps, which the barangay cannot share yet
/// (a migration and Ace's go): nothing fills them today, so they are never drawn.
class CaseStep {
  const CaseStep(this.title, this.time, {this.note, this.thumb});

  final String title;
  final String time;
  final String? note;
  final CaseMedia? thumb;
}

/// The big green Resolved card: the outcome, the tanod's field report as written, the proof photo large, the process as one line.
class CaseResolvedCard extends StatefulWidget {
  const CaseResolvedCard({super.key, required this.words, required this.byTanod, this.proof, this.onOpenProof, required this.steps});

  final String words;

  /// True when a tanod wrote it ("Tanod's field report"), false when the barangay did.
  final bool byTanod;
  final CaseMedia? proof;
  final VoidCallback? onOpenProof;
  final List<CaseStep> steps;

  @override
  State<CaseResolvedCard> createState() => _CaseResolvedCardState();
}

class _CaseResolvedCardState extends State<CaseResolvedCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final rail = t.dark ? const Color(0x803FB868) : const Color(0x73087F31);
    final ring = t.dark ? const Color(0xFF17231B) : const Color(0xFFEAF4EC);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(CaseTokens.doneFill.withValues(alpha: t.dark ? .20 : .09), t.bg),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CaseTokens.doneFill.withValues(alpha: .40)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: CaseTokens.doneFill, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Semantics(header: true, child: Text(context.tr('Resolved', 'Nalutas na'), style: caseTight(t.ink, 21, 26))),
          ]),
          Text(widget.byTanod ? context.tr('Tanod’s field report', 'Ulat ng tanod sa lugar') : context.tr('From the barangay', 'Mula sa barangay'),
              style: caseInter(t.muted, 12, FontWeight.w700, 16)),
        ]),
        const SizedBox(height: 10),
        Text(widget.words, style: caseInter(t.ink, 14.5, FontWeight.w500).copyWith(height: 1.5)),
        if (widget.proof != null) ...[
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: context.tr('Open the proof photo', 'Buksan ang larawang patunay'),
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenProof,
                child: SizedBox(
                  height: _open ? 120 : 150,
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(children: [
                      CaseThumb(media: widget.proof!, size: c.maxWidth, semantics: ''),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: CaseTokens.doneFill, borderRadius: BorderRadius.circular(11)),
                          child: Text(context.tr('Proof', 'Patunay'), textScaler: TextScaler.noScaling, style: caseInter(Colors.white, 11.5, FontWeight.w800, 22)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (!_open) ...[const SizedBox(height: 14), const CaseTrack(done: 4)],
        if (_open) ...[
          const SizedBox(height: 14),
          for (var i = 0; i < widget.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(22, 0, 0, i == widget.steps.length - 1 ? 2 : 16),
                  decoration: BoxDecoration(border: Border(left: BorderSide(width: 2, color: i == widget.steps.length - 1 ? Colors.transparent : rail))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                      Text(widget.steps[i].title, style: caseInter(t.ink, 14, FontWeight.w800, 19)),
                      Text(widget.steps[i].time, style: caseInter(t.muted, 12, FontWeight.w500, 16)),
                    ]),
                    if (widget.steps[i].note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(widget.steps[i].note!, style: caseInter(t.ink2, 13.5, FontWeight.w500).copyWith(height: 1.45))),
                    if (widget.steps[i].thumb != null)
                      Padding(padding: const EdgeInsets.only(top: 6), child: CaseThumb(media: widget.steps[i].thumb!, semantics: context.tr('Photo from this step', 'Larawan mula sa hakbang na ito'))),
                  ]),
                ),
                Positioned(
                  left: -7,
                  top: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: CaseTokens.doneFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: ring, width: 3),
                      boxShadow: const [BoxShadow(color: CaseTokens.doneFill, spreadRadius: 1.5)],
                    ),
                  ),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 10),
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: CaseTokens.doneFill.withValues(alpha: t.dark ? .35 : .30)))),
              child: Row(children: [
                Expanded(
                  child: Text(_open ? context.tr('Hide how it was handled', 'Itago kung paano ito inasikaso') : context.tr('How it was handled', 'Paano ito inasikaso'),
                      style: caseInter(t.ink2, 14, FontWeight.w700)),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: t.muted).rotated(_open ? 90 : 0),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- feedback ------------------------------------------

/// Your feedback: the stars and the words, centred, once the resident has rated the case.
class CaseFeedbackCard extends StatelessWidget {
  const CaseFeedbackCard({super.key, required this.rating, this.comment});

  final int rating;
  final String? comment;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: caseCardBox(t),
      child: Column(children: [
        Text(context.s.reportViewYourFeedback, textAlign: TextAlign.center, style: caseInter(t.navy, 15, FontWeight.w800, 20)),
        const SizedBox(height: 8),
        Semantics(
          label: context.tr('$rating of 5 stars', '$rating sa 5 na bituin'),
          child: ExcludeSemantics(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 28, color: i <= rating ? CaseTokens.orange : t.edge),
                ),
            ]),
          ),
        ),
        if (comment != null && comment!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(comment!.trim(), textAlign: TextAlign.center, style: caseInter(t.muted, 14, FontWeight.w500, 20)),
        ],
      ]),
    );
  }
}

// ---------- buttons and the pinned bar ------------------------

enum CaseButtonKind { primary, ghost, appeal, danger, disabled }

/// Button: 56 high, radius 16, 16/800, the portal's flat shadow under the orange one; [small] is 44.
class CaseButton extends StatelessWidget {
  const CaseButton({super.key, required this.label, required this.onTap, this.kind = CaseButtonKind.primary, this.icon, this.small = false, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final CaseButtonKind kind;
  final IconData? icon;
  final bool small;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    var bg = CaseTokens.orange;
    var fg = const Color(0xFF141B34);
    BorderSide? side;
    Color? shadow = CaseTokens.orange.withValues(alpha: t.dark ? .22 : .30);
    switch (kind) {
      case CaseButtonKind.primary:
        break;
      case CaseButtonKind.ghost:
        bg = t.card;
        fg = t.ink;
        side = BorderSide(color: t.edge, width: 1.5);
        shadow = null;
      case CaseButtonKind.appeal:
        bg = CaseTokens.appealRed;
        fg = Colors.white;
        shadow = CaseTokens.appealRed.withValues(alpha: .30);
      case CaseButtonKind.danger:
        bg = t.card;
        fg = t.dangerInk;
        side = BorderSide(color: t.dark ? const Color(0xFF7A2A34) : const Color(0xFFC4172A), width: 1.5);
        shadow = null;
      case CaseButtonKind.disabled:
        bg = t.dark ? const Color(0xFF2A2D33) : const Color(0xFFDDE2EE);
        fg = t.muted;
        shadow = null;
    }
    final enabled = onTap != null && !busy && kind != CaseButtonKind.disabled;
    final radius = BorderRadius.circular(small ? 14 : 16);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow == null ? null : [BoxShadow(color: shadow, offset: const Offset(0, 5))]),
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(borderRadius: radius, side: side ?? BorderSide.none),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: small ? 44 : 56, minWidth: double.infinity),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: small ? 18 : 22, vertical: 8),
                    child: Center(
                      child: busy
                          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                          : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
                              Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: caseInter(fg, small ? 14 : 16, FontWeight.w800, small ? 18 : 20))),
                            ]),
                    ),
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

/// ActionBar: pinned at the bottom, the one main action and, when there is more to do, a More button before it.
class CaseActionBar extends StatelessWidget {
  const CaseActionBar({super.key, required this.label, required this.onTap, this.kind = CaseButtonKind.primary, this.icon, this.onMore, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final CaseButtonKind kind;
  final IconData? icon;
  final VoidCallback? onMore;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, math.max(16, inset)),
      decoration: BoxDecoration(color: t.card, border: Border(top: BorderSide(color: t.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (onMore != null) ...[
          Semantics(
            button: true,
            label: context.tr('More', 'Iba pa'),
            child: ExcludeSemantics(
              child: Material(
                color: t.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.edge, width: 1.5)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onMore,
                  child: SizedBox(width: 56, height: 56, child: Icon(Icons.more_horiz_rounded, size: 22, color: t.ink)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: CaseButton(label: label, icon: icon, kind: kind, onTap: onTap, busy: busy)),
      ]),
    );
  }
}

// ---------- sheets --------------------------------------------

Future<T?> showCaseSheet<T>(BuildContext context, {required Widget Function(BuildContext, CaseTokens) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.d.dark ? const Color(0x99000000) : const Color(0x7320273B),
    builder: (ctx) {
      final t = CaseTokens.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + MediaQuery.viewPaddingOf(ctx).bottom * 0),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: t.dark ? const Color(0x8C000000) : const Color(0x3820273B), blurRadius: 30, offset: const Offset(0, -8))],
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: t.edge, borderRadius: BorderRadius.circular(3)))),
              builder(ctx, t),
            ]),
          ),
        ),
      );
    },
  );
}

class CaseMoreItem {
  const CaseMoreItem(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The More menu: a bottom sheet of the actions that are not the main one.
Future<void> showCaseMore(BuildContext context, List<CaseMoreItem> items) {
  return showCaseSheet<void>(
    context,
    builder: (ctx, t) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Semantics(header: true, child: Text(ctx.tr('More', 'Iba pa'), style: caseTight(t.ink, 18, 24)))),
      for (final it in items)
        Semantics(
          button: true,
          child: InkWell(
            onTap: () {
              Navigator.of(ctx).pop();
              it.onTap();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.edge))),
              child: Row(children: [
                Icon(it.icon, size: 22, color: it.danger ? t.dangerInk : t.ink),
                const SizedBox(width: 14),
                Expanded(child: Text(it.label, style: caseInter(it.danger ? t.dangerInk : t.ink, 16, FontWeight.w700))),
              ]),
            ),
          ),
        ),
    ]),
  );
}

/// The reason sheet (reopen, and appeal): the reasons to pick from, a line to say more, the one action and Not now.
/// Returns the reason in words, or null when the resident backs out.
Future<String?> showCaseReasonSheet(
  BuildContext context, {
  required String title,
  required String hint,
  required List<String> reasons,
  required String confirmLabel,
  required IconData confirmIcon,
  CaseButtonKind confirmKind = CaseButtonKind.primary,
}) {
  return showCaseSheet<String>(
    context,
    builder: (ctx, t) => _ReasonBody(title: title, hint: hint, reasons: reasons, confirmLabel: confirmLabel, confirmIcon: confirmIcon, confirmKind: confirmKind, t: t),
  );
}

class _ReasonBody extends StatefulWidget {
  const _ReasonBody({required this.title, required this.hint, required this.reasons, required this.confirmLabel, required this.confirmIcon, required this.confirmKind, required this.t});

  final String title;
  final String hint;
  final List<String> reasons;
  final String confirmLabel;
  final IconData confirmIcon;
  final CaseButtonKind confirmKind;
  final CaseTokens t;

  @override
  State<_ReasonBody> createState() => _ReasonBodyState();
}

class _ReasonBodyState extends State<_ReasonBody> {
  int _pick = 0;
  final _more = TextEditingController();

  @override
  void dispose() {
    _more.dispose();
    super.dispose();
  }

  bool get _other => _pick == widget.reasons.length - 1;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final needsWords = _other && _more.text.trim().isEmpty;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(widget.title, style: caseTight(t.ink, 21, 28))),
      const SizedBox(height: 2),
      Text(widget.hint, style: caseInter(t.muted, 13.5, FontWeight.w500, 19)),
      const SizedBox(height: 12),
      for (var i = 0; i < widget.reasons.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          checked: _pick == i,
          label: widget.reasons[i],
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _pick = i),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _pick == i ? CaseTokens.orange.withValues(alpha: t.dark ? .14 : .10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _pick == i ? CaseTokens.orange : t.edge, width: _pick == i ? 2 : 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _pick == i ? CaseTokens.orange : null,
                      border: _pick == i ? null : Border.all(color: t.edge, width: 2),
                    ),
                    child: _pick == i ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF141B34)) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.reasons[i], style: caseInter(t.ink, 15, FontWeight.w700, 20))),
                ]),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _more,
        minLines: 3,
        maxLines: 3,
        maxLength: 300,
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.sentences,
        style: caseInter(t.ink, 14, FontWeight.w500).copyWith(height: 1.45),
        decoration: InputDecoration(
          counterText: '',
          hintText: _other ? context.tr('Tell the barangay why', 'Sabihin sa barangay kung bakit') : context.tr('Tell the barangay more (optional)', 'Sabihin pa sa barangay (opsyonal)'),
          hintStyle: caseInter(t.muted, 14, FontWeight.w500).copyWith(height: 1.45),
          filled: true,
          fillColor: t.field,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.line, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.line, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: t.navy, width: 1.5)),
        ),
      ),
      const SizedBox(height: 14),
      CaseButton(
        label: widget.confirmLabel,
        icon: widget.confirmIcon,
        kind: needsWords ? CaseButtonKind.disabled : widget.confirmKind,
        onTap: needsWords
            ? null
            : () {
                final more = _more.text.trim();
                final base = widget.reasons[_pick];
                Navigator.of(context).pop(_other ? more : (more.isEmpty ? base : '$base: $more'));
              },
      ),
      CaseButton(label: context.tr('Not now', 'Huwag muna'), kind: CaseButtonKind.ghost, onTap: () => Navigator.of(context).pop()),
    ]);
  }
}

/// How many of the four steps are done for a status (the case page's track and the list's bars agree). Under Review is at
/// Validated; once the barangay has accepted it, a tanod is "now"; a finished report is all four.
int caseStepsDone(String wire) => switch (wire) {
      'pending_review' || 'rejected' || 'cancelled' => 1,
      'validated' || 'assigned' || 'in_progress' || 'offline_investigation' => 2,
      _ => 4,
    };

/// The list card's progress: four bars in the case page's colours, green done and orange now. A report that stopped (rejected,
/// cancelled) draws its stop colour on the first bar and nothing after.
class CaseSegments extends StatelessWidget {
  const CaseSegments({super.key, required this.done, this.stop});

  final int done;
  final Color? stop;

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    return Semantics(
      label: stop != null
          ? context.tr('Stopped', 'Huminto')
          : context.tr('Progress: $done of 4 steps done', 'Progreso: $done sa 4 na hakbang ang tapos'),
      child: ExcludeSemantics(
        child: Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: stop != null ? (i == 0 ? stop : t.edge) : (i < done ? CaseTokens.doneFill : (i == done ? CaseTokens.orange : t.edge)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ---------- Where ---------------------------------------------

/// Where: a small map of the place you reported (the pin is the portal's disc in the category's colour and symbol), with the address
/// under it. Two fingers move and zoom the map, so a single finger still scrolls the page past it; the frame button brings the pin
/// back. No zoom buttons and no full-screen, by design. With no signal it is a still placeholder that keeps the address.
class CaseWhereCard extends StatefulWidget {
  const CaseWhereCard({super.key, required this.point, required this.colour, required this.glyph, required this.address, required this.sub});

  final ll.LatLng point;
  final Color colour;

  /// The category's symbol key, as the map's pins use it.
  final String glyph;
  final String address;
  final String sub;

  @override
  State<CaseWhereCard> createState() => _CaseWhereCardState();
}

class _CaseWhereCardState extends State<CaseWhereCard> {
  static const _mapHeight = 170.0;
  bool _offline = false;
  bool _moved = false;
  StreamSubscription<List<ConnectivityResult>>? _net;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
    try {
      _net = Connectivity().onConnectivityChanged.listen((r) {
        if (mounted) setState(() => _offline = !r.any((c) => c != ConnectivityResult.none));
      });
    } catch (_) {}
  }

  Future<void> _check() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _offline = !r.any((c) => c != ConnectivityResult.none));
    } catch (_) {}
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: '${widget.address}, ${widget.sub}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr('Address copied', 'Nakopya ang address'))));
  }

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final map = Semantics(
      container: true,
      label: context.tr('Map of where you reported, ${widget.address}', 'Mapa kung saan mo isinampa, ${widget.address}'),
      child: SizedBox(
        height: _mapHeight,
        child: _offline
            ? Container(
                decoration: BoxDecoration(color: t.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.line)),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: widget.colour, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.place_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('The map shows when you have signal.', 'Lalabas ang mapa kapag may signal ka.'), textAlign: TextAlign.center, style: caseInter(t.muted, 12.5, FontWeight.w600, 17)),
                ]),
              )
            : Stack(children: [
                Positioned.fill(
                  child: BrgyMap(
                    use: BrgyMapUse.place,
                    initialCenter: widget.point,
                    initialZoom: 17,
                    cornerRadius: 14,
                    cornerColour: t.card,
                    fitLabel: context.tr('Back to the pin', 'Balik sa pin'),
                    onMoved: (_) {
                      if (!_moved) setState(() => _moved = true);
                    },
                    pins: [BrgyMapPin(id: 'report', point: widget.point, colour: widget.colour, glyph: widget.glyph)],
                  ),
                ),
                if (!_moved)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: t.card.withValues(alpha: .92), borderRadius: BorderRadius.circular(12)),
                        child: Text(context.tr('Move the map with two fingers', 'Igalaw ang mapa gamit ang dalawang daliri'), style: caseInter(t.ink2, 11.5, FontWeight.w700, 15)),
                      ),
                    ),
                  ),
              ]),
      ),
    );
    return Container(
      decoration: caseCardBox(t),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        map,
        Semantics(
          button: true,
          label: context.tr('${widget.address}. Copy the address', '${widget.address}. Kopyahin ang address'),
          child: ExcludeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _copy,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.only(top: 10, left: 2, right: 2, bottom: 0),
                child: Row(children: [
                  Icon(Icons.place_outlined, size: 22, color: t.navy),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.address, style: caseInter(t.ink, 14.5, FontWeight.w700, 20)),
                      Text(widget.sub, style: caseInter(t.muted, 12.5, FontWeight.w500, 17)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
