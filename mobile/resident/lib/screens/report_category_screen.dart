// SmartSumbong — Submit Report, step 1: which category.
//
// Figma node 2212:145.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../models/complaint_catalogue.dart';
import '../models/complaint_category.dart';

class ReportCategoryScreen extends StatefulWidget {
  const ReportCategoryScreen({super.key});

  @override
  State<ReportCategoryScreen> createState() => _ReportCategoryScreenState();
}

class _ReportCategoryScreenState extends State<ReportCategoryScreen> {
  /// A report keeps to one category (0176) and to three concerns (the database takes four; the form keeps to three).
  /// The concerns are the category's own pills, tapped in any number: the first one tapped is the main concern, the
  /// rest ride with it (Rose, 19 Nov 2026: no "add another" step when they can just be picked from the list).
  static const _maxConcerns = 3;

  ComplaintCategory? _category;
  final List<ComplaintOption> _picked = [];

  /// Others has no pills of its own, so it is picked apart from them.
  bool get _othersPicked => _category == ComplaintCategory.other && _picked.isEmpty;

  /// What Continue carries to the second page.
  CategoryChoice? get _choice {
    final c = _category;
    if (c == null) return null;
    if (_picked.isEmpty) return CategoryChoice(category: c);
    final main = _picked.first;
    return CategoryChoice(
      category: c,
      issue: main.en,
      issueFil: main.fil,
      optionId: main.id,
      extras: [for (final o in _picked.skip(1)) ExtraConcern(c, o)],
    );
  }

  @override
  void initState() {
    super.initState();
    // The barangay may have changed its list since the app opened (0146).
    ComplaintCatalogue.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Another category: the concerns picked here cannot come along, so ask before they go (only when there is more
  /// than one to lose).
  Future<bool> _leaveCategory(ComplaintCategory to) async {
    final from = _category;
    if (from == null || from == to || _picked.length < 2) return true;
    final name = context.tr(from.label, from.labelFil);
    final change = await showDDialog(
      context,
      title: context.tr('Change the category?', 'Palitan ang kategorya?'),
      body: context.tr('A report keeps to one category, so the other concerns you picked under $name will be cleared.',
          'Iisang kategorya lang ang bawat ulat, kaya aalisin ang iba pang concern na pinili mo sa ilalim ng $name.'),
      primary: context.tr('Change category', 'Palitan ang kategorya'),
      secondary: context.tr('Keep $name', 'Manatili sa $name'),
      icon: Icons.category_rounded,
    );
    return change == true && mounted;
  }

  Future<void> _toggle(ComplaintCategory category, ComplaintOption o) async {
    if (_category != category) {
      if (!await _leaveCategory(category)) return;
      setState(() {
        _category = category;
        _picked
          ..clear()
          ..add(o);
      });
      return;
    }
    setState(() {
      final at = _picked.indexWhere((p) => p.en == o.en);
      if (at >= 0) {
        _picked.removeAt(at);
        if (_picked.isEmpty) _category = null;
      } else if (o.id == null || _picked.any((p) => p.id == null)) {
        // The built-in list (before the barangay's has been read) has no ids to send other concerns by: one only.
        _picked
          ..clear()
          ..add(o);
      } else if (_picked.length < _maxConcerns) {
        _picked.add(o);
      }
    });
  }

  Future<void> _pickOthers() async {
    if (_othersPicked || !await _leaveCategory(ComplaintCategory.other)) return;
    setState(() {
      _category = ComplaintCategory.other;
      _picked.clear();
    });
  }

  // Branch D: the preview's category picker — the question and the scope
  // note, then one white card per category with its colour, the issues
  // as pills (each picked one fills with the category's colour and shows a tick; up to three), and Back
  // / Continue pinned at the bottom.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    return DPage(
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              const Align(alignment: Alignment.centerLeft, child: DBack()),
              const SizedBox(height: 12),
              DHeading(s.reportCategoryHeading, lead: s.reportCategorySubtitle),
              const SizedBox(height: 6),
              Text(
                context.tr('Pick every concern that applies, up to $_maxConcerns, from one category.',
                    'Piliin ang lahat ng concern na naaangkop, hanggang $_maxConcerns, mula sa iisang kategorya.'),
                style: DType.body(d.muted, size: 13).copyWith(height: 1.4),
              ),
              const SizedBox(height: 10),
              // Straight from the design, and worth keeping verbatim: it
              // keeps this system inside its scope. Katarungang
              // Pambarangay mediation is not what this app does.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: DColors.red.withValues(alpha: .07),
                  border: Border.all(color: DColors.red.withValues(alpha: .3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: d.dark ? const Color(0xFFFF8A8A) : DColors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.reportCategoryNote, style: DType.body(d.dark ? const Color(0xFFFFB4B4) : const Color(0xFF9B1C1C), size: 12.5))),
                ]),
              ),
              const SizedBox(height: 16),
              for (final c in ComplaintCategory.values.where((c) => c != ComplaintCategory.other)) ...[
                _CategoryCard(
                  category: c,
                  picked: _category == c ? _picked : const [],
                  max: _maxConcerns,
                  onToggle: (o) => _toggle(c, o),
                ),
                const SizedBox(height: 12),
              ],
              // Others stays last, unless the barangay switched it off.
              if (ComplaintCategory.values.contains(ComplaintCategory.other)) _OthersCard(selected: _othersPicked, onPick: _pickOthers),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(children: [
            Expanded(child: DButton(s.reportCategoryBack, kind: DButtonKind.ghost, expand: true, onTap: () => Navigator.of(context).pop())),
            const SizedBox(width: 10),
            Expanded(child: DButton(s.reportCategoryContinue, expand: true, onTap: _choice == null ? null : () => _choose(context, _choice!))),
          ]),
        ),
      ]),
    );
  }
}

/// One category: its colour, its name, its issues as pills (tap any number, up to [max]).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.picked, required this.max, required this.onToggle});

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
    const slop = EdgeInsets.symmetric(vertical: _HitSlop.chip);
    return _Shell(
      colour: col,
      title: context.tr(category.label, category.labelFil),
      reachBelow: true,
      // The first row's touch also reaches up into the gap under the card's title, so the column takes it too.
      child: _HitSlop(
        slop: const EdgeInsets.only(top: _HitSlop.chip),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _HitSlop(
            slop: slop,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in category.options)
                _HitSlop(
                  slop: slop,
                  child: Builder(builder: (context) {
                    final on = picked.any((p) => p.en == o.en);
                    return _IssuePill(label: context.tr(o.en, o.fil), colour: col, selected: on, onTap: full && !on ? null : () => onToggle(o));
                  }),
                ),
            ]),
          ),
          if (picked.isNotEmpty && category.options.where((o) => o.id != null).length > 1) ...[
            const SizedBox(height: 10),
            Text(context.tr('${picked.length} of $max picked', '${picked.length} sa $max ang napili'),
                style: DType.body(context.d.muted, size: 12.5, w: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

class _OthersCard extends StatelessWidget {
  const _OthersCard({required this.selected, required this.onPick});

  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final col = categoryColour(ComplaintCategory.parse('other'));
    return _Shell(
      colour: col,
      title: context.s.reportCategoryOthersHeading,
      child: _IssuePill(
        label: context.s.reportCategoryOthers,
        colour: col,
        selected: selected,
        // Its own category since 0076.
        onTap: onPick,
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.colour, required this.title, required this.child, this.reachBelow = false});

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
              child: _HitSlop(
                slop: EdgeInsets.only(bottom: reachBelow ? _HitSlop.chip : 0),
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
class _IssuePill extends StatelessWidget {
  const _IssuePill({required this.label, required this.colour, required this.onTap, this.selected = false});

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

void _choose(BuildContext context, CategoryChoice choice) {
  Navigator.of(context).pushNamed('/submit-report/details', arguments: choice);
}

/// Takes taps up to [slop] outside its child and hands them to the child at its nearest edge, so a small target answers
/// a 48 x 48 touch (Android's minimum) without being drawn any bigger. Every box up the tree must reach the tap too,
/// which is why the chips' Wrap and the card's column carry one as well.
class _HitSlop extends SingleChildRenderObjectWidget {
  const _HitSlop({required this.slop, required super.child});

  /// What a 30 px chip needs above and below to make 48.
  static const chip = 9.0;

  final EdgeInsets slop;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlop(slop);

  @override
  void updateRenderObject(BuildContext context, _RenderHitSlop renderObject) => renderObject.slop = slop;
}

class _RenderHitSlop extends RenderProxyBox {
  _RenderHitSlop(this.slop);

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
