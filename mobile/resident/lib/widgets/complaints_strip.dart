// SmartSumbong — "Your complaints": the strip of pills for what the resident picked on the first page of a
// report (the main concern and up to two more), and the sheet that lists them. 19 Nov 2026, from the Where
// is it? design (Strip, S1).
//
// The strip shows one or two pills in the category's colour and "+N" for the rest; tapping it opens the sheet.
// The sheet is read-only for now: the concerns are changed on the first page (Back).

import 'package:flutter/material.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../models/complaint_category.dart';

/// The names of what was picked, in the app's language: the main concern first, then the others.
List<String> complaintNames(BuildContext context, CategoryChoice choice) => [
      context.tr(choice.issue ?? choice.category.label, choice.issueFil ?? choice.issue ?? choice.category.labelFil),
      for (final x in choice.extras) context.tr(x.option?.en ?? x.category.label, x.option?.fil ?? x.category.labelFil),
    ];

class ComplaintsStrip extends StatelessWidget {
  const ComplaintsStrip({super.key, required this.choice, this.shown = 2});

  final CategoryChoice choice;

  /// How many pills before "+N".
  final int shown;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final col = categoryColour(choice.category);
    final names = complaintNames(context, choice);
    final more = names.length - shown;
    return Semantics(
      button: true,
      label: context.tr('Your complaints: ${names.length}. Tap to see all', 'Ang iyong mga reklamo: ${names.length}. I-tap para makita lahat'),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => showComplaintsSheet(context, choice),
        // 44 high to touch, though the pills are drawn 30
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final n in names.take(shown)) _Pill(n, col),
              if (more > 0)
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: d.dark ? const Color(0xFF4A4F57) : const Color(0xFFC3CBDD)),
                  ),
                  child: Center(widthFactor: 1, child: Text('+$more', style: DType.body(d.ink2, size: 12.5, w: FontWeight.w800).copyWith(height: 1))),
                ),
            ]),
          ),
        ),
      ),
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 80),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: d.dark ? .22 : .12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colour.withValues(alpha: .6)),
        ),
        child: Center(widthFactor: 1, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 12.5, w: FontWeight.w700).copyWith(height: 1))),
      ),
    );
  }
}

/// The sheet "Your complaints": everything picked, under the category. Read-only for now.
Future<void> showComplaintsSheet(BuildContext context, CategoryChoice choice) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.d.bg,
    barrierColor: Colors.black.withValues(alpha: context.d.dark ? .6 : .45),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      final d = ctx.d;
      final col = categoryColour(choice.category);
      final names = complaintNames(ctx, choice);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(ctx.tr('Your complaints', 'Ang iyong mga reklamo'), style: DType.h2(d.ink).copyWith(fontSize: 22))),
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
              const SizedBox(height: 8),
              Text(ctx.tr('These are what you picked on the first page. Go back to change them.', 'Ito ang mga pinili mo sa unang pahina. Bumalik para baguhin ang mga ito.'),
                  style: DType.body(d.muted, size: 13)),
              const SizedBox(height: 16),
              Container(
                decoration: d.cardBox(18),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(width: 6, color: col),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(ctx.tr(choice.category.label, choice.category.labelFil), style: DType.body(d.ink, size: 15, w: FontWeight.w800))),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final n in names)
                              Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                        decoration: BoxDecoration(
                                  color: col,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [BoxShadow(color: col.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Center(widthFactor: 1, child: Text(n, style: DType.body(Colors.white, size: 12.5, w: FontWeight.w700).copyWith(height: 1))),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              DButton(ctx.tr('Done', 'Tapos na'), expand: true, onTap: () => Navigator.of(ctx).pop()),
            ]),
          ),
        ),
      );
    },
  );
}
