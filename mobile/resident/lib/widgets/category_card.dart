// SmartSumbong — one category's card with its concerns as pills: the same widget on the first page of a report and in
// the "Your complaints" sheet (S1), so a pill is picked, ticked, counted and faded the same way in both (19 Nov 2026).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../models/complaint_category.dart';

/// A report keeps to one category (0176) and to three concerns (the database takes four; the form keeps to three).
const maxConcerns = 3;

/// What the counter under the pills says: "2 of 3 picked", and at the limit how to swap one.
String concernCounter(BuildContext context, int picked, int max) => picked >= max
    ? context.tr('$picked of $max picked · tap one to swap', '$picked sa $max ang napili · i-tap ang isa para palitan')
    : context.tr('$picked of $max picked', '$picked sa $max ang napili');

/// One category: its colour, its name, its issues as pills (tap any number, up to [max]).
class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.category, required this.picked, required this.max, required this.onToggle});

  final ComplaintCategory category;

  /// What is picked under this category (empty when another category, or none, is the chosen one).
  final List<ComplaintOption> picked;
  final int max;
  final void Function(ComplaintOption) onToggle;

  @override
  Widget build(BuildContext context) {
    final col = categoryColour(category);
    final full = picked.length >= max;
    // Each pill answers a 48 px tall touch though it is drawn 30 tall: the slop reaches into the gaps around it.
    const slop = EdgeInsets.symmetric(vertical: HitSlop.chip);
    return CategoryShell(
      colour: col,
      title: context.tr(category.label, category.labelFil),
      reachBelow: true,
      // The first row's touch also reaches up into the gap under the card's title, so the column takes it too.
      child: HitSlop(
        slop: const EdgeInsets.only(top: HitSlop.chip),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HitSlop(
            slop: slop,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in category.options)
                HitSlop(
                  slop: slop,
                  child: Builder(builder: (context) {
                    final on = picked.any((p) => p.en == o.en);
                    return ConcernPill(label: context.tr(o.en, o.fil), colour: col, selected: on, onTap: full && !on ? null : () => onToggle(o));
                  }),
                ),
            ]),
          ),
          if (picked.isNotEmpty && category.options.where((o) => o.id != null).length > 1) ...[
            const SizedBox(height: 10),
            Text(concernCounter(context, picked.length, max),
                style: DType.body(context.d.muted, size: 12.5, w: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

class CategoryShell extends StatelessWidget {
  const CategoryShell({super.key, required this.colour, required this.title, required this.child, this.reachBelow = false});

  final Color colour;
  final String title;
  final Widget child;

  /// Lets a tap in the card's bottom padding reach the last row (the pills' 48 px targets).
  final bool reachBelow;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: d.cardBox(18),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: colour),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: HitSlop(
                slop: EdgeInsets.only(bottom: reachBelow ? HitSlop.chip : 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: colour)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: DType.body(d.ink, size: 15, w: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 10),
                  child,
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A concern as a pill: tap to pick it, tap again to put it down. Picked, it fills with the category's colour and
/// shows a tick (so it reads as one of several, not as the only one). Out of picks, the unpicked ones fade ([onTap] null).
class ConcernPill extends StatelessWidget {
  const ConcernPill({super.key, required this.label, required this.colour, required this.onTap, this.selected = false});

  final String label;
  final Color colour;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            // The preview's compact chip (Ace, 7 Oct 2026): 30 tall, 12 in,
            // 12.5 text, the edge tinted with the category's colour.
            constraints: const BoxConstraints(minHeight: 30),
            padding: EdgeInsets.fromLTRB(selected ? 9 : 12, 6, 12, 6),
            decoration: BoxDecoration(
              color: selected ? colour : d.field,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: selected ? colour : Color.lerp(d.line, colour, .45)!),
              boxShadow: selected ? [BoxShadow(color: colour.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4))] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[const Icon(Icons.check_rounded, size: 14, color: Colors.white), const SizedBox(width: 4)],
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 12.5,
                        color: selected ? Colors.white : d.ink)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Takes taps up to [slop] outside its child and hands them to the child at its nearest edge, so a small target answers
/// a 48 x 48 touch (Android's minimum) without being drawn any bigger. Every box up the tree must reach the tap too,
/// which is why the chips' Wrap and the card's column carry one as well.
class HitSlop extends SingleChildRenderObjectWidget {
  const HitSlop({super.key, required this.slop, required super.child});

  /// What a 30 px chip needs above and below to make 48.
  static const chip = 9.0;

  final EdgeInsets slop;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHitSlop(slop);

  @override
  void updateRenderObject(BuildContext context, RenderHitSlop renderObject) => renderObject.slop = slop;
}

class RenderHitSlop extends RenderProxyBox {
  RenderHitSlop(this.slop);

  EdgeInsets slop;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null || !slop.inflateRect(Offset.zero & size).contains(position)) return false;
    final inside = Offset(
      position.dx.clamp(0.0, math.max(0.0, size.width - .01)),
      position.dy.clamp(0.0, math.max(0.0, size.height - .01)),
    );
    if (!c.hitTest(result, position: inside)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
