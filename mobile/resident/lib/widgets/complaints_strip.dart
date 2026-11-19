// SmartSumbong — "Your complaints": the strip of pills for what the resident picked on the first page of a
// report, and the sheet that lists them and changes them. 19 Nov 2026, from the Where is it? design (Strip, S1).
//
// The strip is ONE row: up to two pills in the category's colour, the main concern first, and "+N" for the rest
// (a long name is cut with an ellipsis rather than pushing a pill onto a second line). With [all] it shows every
// pill and wraps, as the context at the top of the Describe pop-up. Tapping it opens the sheet: the category's
// card exactly as on the first page (the same widget), where a pill is ticked or put down (up to three, one
// category), See all categories (back to the first page, keeping the picks) and Done.

import 'package:flutter/material.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../models/complaint_category.dart';
import 'category_card.dart';
import 'd_form.dart';

/// The names of what was picked, in the app's language: the main concern first, then the others.
List<String> complaintNames(BuildContext context, CategoryChoice choice) => [
      context.tr(choice.issue ?? choice.category.label, choice.issueFil ?? choice.issue ?? choice.category.labelFil),
      for (final x in choice.extras) context.tr(x.option?.en ?? x.category.label, x.option?.fil ?? x.category.labelFil),
    ];

class ComplaintsStrip extends StatelessWidget {
  const ComplaintsStrip({super.key, required this.choice, this.onChanged, this.onSeeAll, this.all = false});

  final CategoryChoice choice;

  /// The picks changed in the sheet. Null: the strip only shows them (the Describe pop-up).
  final ValueChanged<CategoryChoice>? onChanged;

  /// See all categories, from the sheet: the screen goes back to the first page.
  final VoidCallback? onSeeAll;

  /// Every pill, wrapping, instead of two and "+N".
  final bool all;

  Future<void> _open(BuildContext context) async {
    final res = await showComplaintsSheet(context, choice);
    if (res.choice != null) onChanged?.call(res.choice!);
    if (res.seeAll) onSeeAll?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final col = categoryColour(choice.category);
    final names = complaintNames(context, choice);
    final Widget pills;
    if (all) {
      pills = Wrap(spacing: 6, runSpacing: 6, children: [for (final n in names) _Pill(n, col)]);
    } else {
      final shown = names.take(2).toList();
      final more = names.length - shown.length;
      pills = Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Flexible(child: _Pill(shown[i], col)),
        ],
        if (more > 0) ...[
          const SizedBox(width: 6),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: d.dark ? const Color(0xFF4A4F57) : const Color(0xFFC3CBDD)),
            ),
            child: Center(widthFactor: 1, child: Text('+$more', style: DType.body(d.ink2, size: 12.5, w: FontWeight.w800).copyWith(height: 1))),
          ),
        ],
      ]);
    }
    // 44 high to touch, though the pills are drawn 30
    final body = ConstrainedBox(constraints: BoxConstraints(minHeight: all ? 0 : 44), child: Align(alignment: Alignment.centerLeft, child: pills));
    if (onChanged == null) return body;
    return Semantics(
      button: true,
      label: context.tr('Your complaints: ${names.length}. Tap to see all', 'Ang iyong mga reklamo: ${names.length}. I-tap para makita lahat'),
      excludeSemantics: true,
      child: InkWell(borderRadius: BorderRadius.circular(15), onTap: () => _open(context), child: body),
    );
  }
}

/// A concern as a pill: the category's colour, lightly filled, the name in ink.
class _Pill extends StatelessWidget {
  const _Pill(this.label, this.colour);

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: d.dark ? .22 : .12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colour.withValues(alpha: .6)),
      ),
      child: Center(widthFactor: 1, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 12.5, w: FontWeight.w700).copyWith(height: 1))),
    );
  }
}

/// What the sheet hands back: the picks as they ended ([choice], null when nothing changed), and whether See all
/// categories was pressed.
class ComplaintsResult {
  const ComplaintsResult({this.choice, this.seeAll = false});

  final CategoryChoice? choice;
  final bool seeAll;
}

bool _same(List<ComplaintOption> a, List<ComplaintOption> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].en == b[i].en].every((x) => x);

/// The sheet "Your complaints" (S1): tall, the category's card with its pills ticked, the counter and the swap rule,
/// See all categories and Done. Every dismissal (Done, the cross, a tap outside, Back) keeps what was picked.
Future<ComplaintsResult> showComplaintsSheet(BuildContext context, CategoryChoice choice) async {
  final before = choice.concernOptions;
  var picked = before;
  var seeAll = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.d.bg,
    barrierColor: Colors.black.withValues(alpha: context.d.dark ? .6 : .45),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      final d = ctx.d;
      final height = MediaQuery.sizeOf(ctx).height - 72;
      return SizedBox(
        height: height,
        child: StatefulBuilder(builder: (ctx, set) {
          final cat = choice.category;
          final col = categoryColour(cat);
          return Column(children: [
            const SizedBox(height: 8),
            Container(width: 44, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 13, 14, 0),
              child: Row(children: [
                Expanded(child: Text(ctx.tr('Your complaints', 'Ang iyong mga reklamo'), style: DType.h2(d.ink).copyWith(fontSize: 22, height: 28 / 22))),
                Semantics(
                  button: true,
                  label: ctx.tr('Close', 'Isara'),
                  excludeSemantics: true,
                  child: Material(
                    color: d.card,
                    shape: CircleBorder(side: BorderSide(color: d.line)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, size: 20, color: d.ink)),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    ctx.tr('Tap a pill to add or remove it, up to $maxConcerns. A report keeps to one category.',
                        'I-tap ang pill para magdagdag o mag-alis, hanggang $maxConcerns. Iisang kategorya lang ang bawat ulat.'),
                    style: DType.body(d.muted, size: 13).copyWith(height: 18 / 13)),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  if (cat.options.isEmpty)
                    // "Others" has no pills of its own
                    CategoryShell(
                      colour: col,
                      title: ctx.tr(cat.label, cat.labelFil),
                      child: ConcernPill(label: ctx.tr(cat.label, cat.labelFil), colour: col, selected: true, onTap: () {}),
                    )
                  else
                    CategoryCard(
                      category: cat,
                      picked: picked,
                      max: maxConcerns,
                      onToggle: (o) {
                        final next = toggleConcern(picked, o, max: maxConcerns);
                        // a report keeps at least one concern
                        if (next.isNotEmpty) set(() => picked = next);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 19 + MediaQuery.paddingOf(ctx).bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DFormButton(ctx.tr('See all categories', 'Tingnan ang lahat ng kategorya'), kind: DFormKind.ghost, onTap: () {
                  seeAll = true;
                  Navigator.of(ctx).pop();
                }),
                const SizedBox(height: 2),
                DFormButton(ctx.tr('Done', 'Tapos na'), onTap: () => Navigator.of(ctx).pop()),
              ]),
            ),
          ]);
        }),
      );
    },
  );
  final changed = choice.category.options.isNotEmpty && !_same(before, picked);
  return ComplaintsResult(choice: changed ? choice.withConcerns(picked) : null, seeAll: seeAll);
}
