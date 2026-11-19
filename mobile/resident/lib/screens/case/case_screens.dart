// SmartSumbong: the case screen's two pages, the full timeline (canvas TL1) and the evidence viewer (EV1, EV2).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../../d/d_ui.dart';
import '../../i18n.dart';
import 'case_ui.dart';

// ---------- the full timeline ---------------------------------

/// One event of the full timeline: when, what happened, and the evidence that goes with it.
class CaseEvent {
  const CaseEvent({
    required this.title,
    required this.time,
    this.body,
    this.now = false,
    this.thumbs = const [],
    this.thumbLabel,
    this.colour = CaseTokens.doneFill,
    this.icon = Icons.check_rounded,
  });

  /// The stage's colour: green done, blue while a tanod is on it, red or grey when it stopped, violet for what you asked.
  final Color colour;
  final IconData icon;

  final String title;
  final String time;
  final String? body;

  /// The orange "Now" row at the top of a report that is still moving; every other row is done (green).
  final bool now;
  final List<CaseMedia> thumbs;
  final String? thumbLabel;
}

/// Full timeline: newest first, on the portal's rail (green done, orange now), each event with its time, a line of what
/// happened and its evidence (your photos at Filed, the barangay's proof where a concern was resolved).
class CaseTimelineScreen extends StatelessWidget {
  const CaseTimelineScreen({super.key, required this.ticket, required this.category, required this.events});

  final String ticket;
  final String category;
  final List<CaseEvent> events;

  static Future<void> open(BuildContext context, CaseTimelineScreen screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: t.bg,
      body: ListView(
        padding: EdgeInsets.fromLTRB(18, top + 8, 18, 40 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              button: true,
              label: context.tr('Back', 'Bumalik'),
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: t.card, shape: BoxShape.circle, border: Border.all(color: t.edge)),
                    child: Icon(Icons.chevron_left_rounded, size: 28, color: t.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(context.tr('Full timeline', 'Buong timeline'), style: caseTight(t.ink, 22, 28))),
                  Text('$ticket · $category', style: caseInter(t.muted, 12.5, FontWeight.w500, 17)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 26),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(context.tr('Nothing has happened on this report yet.', 'Wala pang nangyayari sa ulat na ito.'), textAlign: TextAlign.center, style: caseInter(t.muted, 14, FontWeight.w500, 20)),
            ),
          for (var i = 0; i < events.length; i++) _EventRow(event: events[i], nextColour: i == events.length - 1 ? null : events[i + 1].colour, t: t),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.nextColour, required this.t});

  final CaseEvent event;

  /// The colour of the next (older) node, or null on the last row: the connector fades from this node's colour into it.
  final Color? nextColour;
  final CaseTokens t;

  @override
  Widget build(BuildContext context) {
    final col = event.now ? CaseTokens.orange : event.colour;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the stage node and the connector to the next one, as the track draws them, turned upright
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 1, bottom: 3),
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                boxShadow: event.now ? [BoxShadow(color: CaseTokens.orange.withValues(alpha: t.dark ? .32 : .28), spreadRadius: 4)] : null,
              ),
              child: event.now
                  ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))
                  : Icon(event.icon, size: 15, color: Colors.white),
            ),
            if (nextColour != null)
              Expanded(
                child: Container(
                  width: 4,
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [col, nextColour!]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: nextColour == null ? 0 : 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, style: caseInter(t.ink, 15, FontWeight.w800, 20)),
              Text(event.time, style: caseInter(t.muted, 12.5, FontWeight.w500, 17)),
              if (event.body != null && event.body!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(event.body!, style: caseInter(t.ink2, 13.5, FontWeight.w500).copyWith(height: 1.45))),
              if (event.thumbs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (var i = 0; i < event.thumbs.length && i < 3; i++)
                      CaseThumb(
                        media: event.thumbs[i],
                        semantics: event.thumbs[i].fromBarangay
                            ? context.tr('Barangay proof ${i + 1} of ${event.thumbs.length}', 'Patunay ng barangay ${i + 1} sa ${event.thumbs.length}')
                            : context.tr('Your photo ${i + 1} of ${event.thumbs.length}', 'Larawan mo ${i + 1} sa ${event.thumbs.length}'),
                        onTap: () => CaseViewer.open(context, event.thumbs, i),
                      ),
                    if (event.thumbLabel != null) Text(event.thumbLabel!, style: caseInter(t.muted, 12, FontWeight.w700, 16)),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------- the evidence viewer -------------------------------

/// The viewer for a case's photos and videos: black, a round close button, "1 of 3", the picture, dots, and under it a caption
/// (a tag, a headline, when it was sent and the words with it). Your own photos carry the report's description as theirs.
class CaseViewer extends StatefulWidget {
  const CaseViewer({super.key, required this.items, required this.initial});

  final List<CaseMedia> items;
  final int initial;

  static void open(BuildContext context, List<CaseMedia> items, int index) {
    if (items.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CaseViewer(items: items, initial: index.clamp(0, items.length - 1))));
  }

  @override
  State<CaseViewer> createState() => _CaseViewerState();
}

class _CaseViewerState extends State<CaseViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  static String _when(BuildContext context, DateTime? at) {
    if (at == null) return '';
    final d = at.toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${context.s.monthAbbr(d.month)} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final cur = items[_i];
    const ink = Color(0xFFF3F3F3);
    final tagFill = cur.fromBarangay ? CaseTokens.doneFill : DStatusPill.progress;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0E),
      body: Column(children: [
        SizedBox(
          height: top + 60,
          child: Stack(children: [
            Positioned(
              left: 18,
              top: top + 8,
              child: Semantics(
                button: true,
                label: context.tr('Close', 'Isara'),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 20, color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 76,
              right: 76,
              top: top + 19,
              child: Center(child: Text(context.tr('${_i + 1} of ${items.length}', '${_i + 1} sa ${items.length}'), style: caseInter(ink, 14, FontWeight.w800, 22))),
            ),
          ]),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final m = items[i];
              if (m.isVideo) return InlineVideoPlayer(url: m.url);
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: m.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => _viewerBackdrop(m),
                    errorWidget: (_, _, _) => Container(
                      color: m.fromBarangay ? const Color(0xFF223328) : const Color(0xFF2B3140),
                      alignment: Alignment.center,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.image_outlined, size: 72, color: Colors.white.withValues(alpha: .5)),
                        const SizedBox(height: 8),
                        Text(context.s.reportViewCouldNotLoadPhoto, style: caseInter(Colors.white.withValues(alpha: .7), 13, FontWeight.w500)),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < items.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == _i ? Colors.white : Colors.white.withValues(alpha: .35)),
                ),
            ]),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 24 + MediaQuery.viewPaddingOf(context).bottom),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: tagFill, borderRadius: BorderRadius.circular(12)),
                child: Center(widthFactor: 1, child: Text(cur.fromBarangay ? context.tr('From the barangay', 'Mula sa barangay') : context.tr('Your photo', 'Larawan mo'), textScaler: TextScaler.noScaling, style: caseInter(Colors.white, 11.5, FontWeight.w800, 14))),
              ),
              const SizedBox(height: 10),
              Text(cur.title ?? (cur.fromBarangay ? context.tr('Proof of resolution', 'Patunay ng paglutas') : context.tr('What you sent', 'Ipinadala mo')), style: caseTight(ink, 20, 26)),
              if (cur.at != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_when(context, cur.at), style: caseInter(const Color(0xFFA8A8A8), 13, FontWeight.w500, 18))),
              if (cur.text != null && cur.text!.trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(cur.text!.trim(), maxLines: 5, overflow: TextOverflow.ellipsis, style: caseInter(const Color(0xFFC9CCD1), 14, FontWeight.w500).copyWith(height: 1.45))),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// What shows while a picture loads: the canvas' soft gradient with the picture mark, so the page is never an empty black slab.
Widget _viewerBackdrop(CaseMedia m) => Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: m.fromBarangay ? const [Color(0xFF3B5A47), Color(0xFF223328)] : const [Color(0xFF4A5266), Color(0xFF2B3140)]),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 72, color: Colors.white.withValues(alpha: .5)),
    );
