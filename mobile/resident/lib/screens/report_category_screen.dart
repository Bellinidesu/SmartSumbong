// SmartSumbong — Submit Report, step 1: which category.
//
// Figma node 2212:145.

import 'package:flutter/material.dart';

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

/// "Others" has no issue of its own, so it is keyed apart from the
/// category it files under.
const _othersKey = 'others';

String _keyOf(CategoryChoice c) => '${c.category.wire}|${c.issue}';

class _ReportCategoryScreenState extends State<ReportCategoryScreen> {
  // Tapping a pill picks it; Continue (per the frame) advances with it.
  CategoryChoice? _choice;
  String? _choiceKey;

  /// The other concerns, picked here under the chosen category (Rose, 18 Nov 2026: on the first page, not under
  /// the description on the second; and one category per report, which 0176 enforces).
  final List<ExtraConcern> _extras = [];

  @override
  void initState() {
    super.initState();
    // The barangay may have changed its list since the app opened (0146).
    ComplaintCatalogue.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _pick(String key, CategoryChoice choice) async {
    final was = _choice;
    // Another category: the other concerns cannot come along, so ask before they go.
    if (was != null && was.category != choice.category && _extras.isNotEmpty) {
      final from = context.tr(was.category.label, was.category.labelFil);
      final change = await showDDialog(
        context,
        title: context.tr('Change the category?', 'Palitan ang kategorya?'),
        body: context.tr('A report keeps to one category, so the other concerns you added under $from will be removed.',
            'Iisang kategorya lang ang bawat ulat, kaya aalisin ang iba pang concern na idinagdag mo sa ilalim ng $from.'),
        primary: context.tr('Change category', 'Palitan ang kategorya'),
        secondary: context.tr('Keep $from', 'Manatili sa $from'),
        icon: Icons.category_rounded,
      );
      if (change != true || !mounted) return;
    }
    setState(() {
      if (was?.category != choice.category) _extras.clear();
      // The one now picked as the main concern is no longer one of the others.
      _extras.removeWhere((x) => x.option != null && x.option!.en == choice.issue);
      _choiceKey = key;
      _choice = choice;
    });
  }

  // Branch D: the preview's category picker — the question and the scope
  // note, then one white card per category with its colour, the issues
  // as pills (the picked one fills with the category's colour), and Back
  // / Continue pinned at the bottom.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    // Only under the chosen category, and only when it has another option to add (Others has none).
    Widget? more(ComplaintCategory c) => _choice?.category == c && (_extras.isNotEmpty || _MoreConcerns.left(_choice!, _extras).isNotEmpty)
        ? _MoreConcerns(
            main: _choice!,
            extras: _extras,
            onAdd: (x) => setState(() => _extras.add(x)),
            onRemove: (x) => setState(() => _extras.remove(x)),
          )
        : null;
    return DPage(
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              const Align(alignment: Alignment.centerLeft, child: DBack()),
              const SizedBox(height: 12),
              DHeading(s.reportCategoryHeading, lead: s.reportCategorySubtitle),
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
                _CategoryCard(category: c, selectedKey: _choiceKey, onPick: _pick, more: more(c)),
                const SizedBox(height: 12),
              ],
              // Others stays last, unless the barangay switched it off.
              if (ComplaintCategory.values.contains(ComplaintCategory.other)) _OthersCard(selected: _choiceKey == _othersKey, onPick: _pick),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(children: [
            Expanded(child: DButton(s.reportCategoryBack, kind: DButtonKind.ghost, expand: true, onTap: () => Navigator.of(context).pop())),
            const SizedBox(width: 10),
            Expanded(child: DButton(s.reportCategoryContinue, expand: true, onTap: _choice == null ? null : () => _choose(context, _choice!.withExtras(_extras)))),
          ]),
        ),
      ]),
    );
  }
}

/// One category: its colour, its name, its issues as pills.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.selectedKey, required this.onPick, this.more});

  final ComplaintCategory category;
  final String? selectedKey;
  final void Function(String key, CategoryChoice choice) onPick;

  /// The other concerns, under the chosen category's own pills.
  final Widget? more;

  @override
  Widget build(BuildContext context) {
    final col = categoryColour(category);
    return _Shell(
      colour: col,
      title: context.tr(category.label, category.labelFil),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in category.options)
            Builder(builder: (context) {
              final choice = CategoryChoice(category: category, issue: o.en, issueFil: o.fil, optionId: o.id);
              final key = _keyOf(choice);
              return _IssuePill(label: context.tr(o.en, o.fil), colour: col, selected: selectedKey == key, onTap: () => onPick(key, choice));
            }),
        ]),
        ?more,
      ]),
    );
  }
}

class _OthersCard extends StatelessWidget {
  const _OthersCard({required this.selected, required this.onPick});

  final bool selected;
  final void Function(String key, CategoryChoice choice) onPick;

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
        onTap: () => onPick(_othersKey, CategoryChoice(category: ComplaintCategory.parse('other'))),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.colour, required this.title, required this.child});

  final Color colour;
  final String title;
  final Widget child;

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
        ]),
      ),
    );
  }
}

class _IssuePill extends StatelessWidget {
  const _IssuePill({required this.label, required this.colour, required this.onTap, this.selected = false});

  final String label;
  final Color colour;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // The preview's compact chip (Ace, 7 Oct 2026): 30 tall, 12 in,
          // 12.5 text, the edge tinted with the category's colour.
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colour : d.field,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? colour : Color.lerp(d.line, colour, .45)!),
            boxShadow: selected ? [BoxShadow(color: colour.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4))] : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                  color: selected ? Colors.white : d.ink)),
        ),
      ),
    );
  }
}

void _choose(BuildContext context, CategoryChoice choice) {
  Navigator.of(context).pushNamed('/submit-report/details', arguments: choice);
}

/// "Is there more than one problem?" (0163), under the chosen category's pills: the other concerns as chips, and a
/// sheet to add one. Only this category's options are offered; a report keeps to one category (0176).
class _MoreConcerns extends StatelessWidget {
  const _MoreConcerns({required this.main, required this.extras, required this.onAdd, required this.onRemove});

  /// The database takes four concerns; the form keeps to three (the main one and two more).
  static const max = 2;

  final CategoryChoice main;
  final List<ExtraConcern> extras;
  final void Function(ExtraConcern) onAdd;
  final void Function(ExtraConcern) onRemove;

  /// What can still be added: the category's options with a row id (a concern points at it), less the main one
  /// and those already added.
  static List<ComplaintOption> left(CategoryChoice main, List<ExtraConcern> extras) => [
        for (final o in main.category.options)
          if (o.id != null && o.en != main.issue && !extras.any((x) => x.option?.id == o.id)) o,
      ];

  Future<void> _pick(BuildContext context) async {
    final d = context.d;
    final col = categoryColour(main.category);
    final picked = await showModalBottomSheet<ExtraConcern>(
      context: context,
      isScrollControlled: true,
      backgroundColor: d.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 18), shrinkWrap: true, children: [
            Text(ctx.tr('Add another concern', 'Magdagdag ng isa pang concern'), style: DType.body(d.ink, size: 16, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(ctx.tr('Pick what else is wrong. Each one is looked at, and resolved, on its own. A report keeps to one category.',
                    'Piliin kung ano pa ang problema. Bawat isa ay titingnan, at aayusin, nang hiwalay. Iisang kategorya lang ang bawat ulat.'),
                style: DType.body(d.muted, size: 12.5)),
            const SizedBox(height: 12),
            Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
              const SizedBox(width: 7),
              Expanded(child: Text(ctx.tr(main.category.label, main.category.labelFil).toUpperCase(), style: DType.label(d.muted))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in left(main, extras))
                _ConcernPill(label: ctx.tr(o.en, o.fil), colour: col, onTap: () => Navigator.of(ctx).pop(ExtraConcern(main.category, o))),
            ]),
          ]),
        ),
      ),
    );
    if (picked != null) onAdd(picked);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final col = categoryColour(main.category);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      Divider(height: 1, thickness: 1, color: d.line),
      const SizedBox(height: 12),
      Text(context.tr('Is there more than one problem? (optional)', 'May iba pa bang problema? (opsyonal)'), style: DType.body(d.ink, size: 13.5, w: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in extras)
          _ExtraChip(label: context.tr(x.option!.en, x.option!.fil), colour: col, onRemove: () => onRemove(x)),
        if (extras.length < max && left(main, extras).isNotEmpty)
          _AddChip(colour: col, onTap: () => _pick(context)),
      ]),
    ]);
  }
}

class _ConcernPill extends StatelessWidget {
  const _ConcernPill({required this.label, required this.colour, required this.onTap});

  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: colour.withValues(alpha: .12),
        shape: StadiumBorder(side: BorderSide(color: colour.withValues(alpha: .6))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(label, style: DType.body(context.d.ink, size: 13, w: FontWeight.w700))),
        ),
      );
}

/// Another concern, picked: the issue pill's size, tinted with the category's colour, with a remove cross.
class _ExtraChip extends StatelessWidget {
  const _ExtraChip({required this.label, required this.colour, required this.onRemove});

  final String label;
  final Color colour;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: d.dark ? .22 : .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colour.withValues(alpha: .6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5).copyWith(color: d.ink))),
        const SizedBox(width: 2),
        Tooltip(
          message: '${context.tr('Remove', 'Alisin')} $label',
          child: InkResponse(
            onTap: onRemove,
            radius: 16,
            child: SizedBox(width: 26, height: 28, child: Icon(Icons.close_rounded, size: 16, color: d.muted)),
          ),
        ),
      ]),
    );
  }
}

/// "+ Add another concern": an outlined pill in the category's colour.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.colour, required this.onTap});

  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.only(left: 8, right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Color.lerp(d.line, colour, .45)!),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 18, color: colour),
            const SizedBox(width: 4),
            Text(context.tr('Add another concern', 'Magdagdag ng isa pang concern'),
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5).copyWith(color: d.ink)),
          ]),
        ),
      ),
    );
  }
}
