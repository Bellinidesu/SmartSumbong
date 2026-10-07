// SmartSumbong — Submit Report, step 1: which category.
//
// Figma node 2212:145.

import 'package:flutter/material.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../models/complaint_category.dart';

class ReportCategoryScreen extends StatefulWidget {
  const ReportCategoryScreen({super.key});

  @override
  State<ReportCategoryScreen> createState() => _ReportCategoryScreenState();
}

/// "Others" has no issue of its own, so it is keyed apart from the
/// category it files under.
const _othersKey = 'others';

String _keyOf(CategoryChoice c) => '${c.category.name}|${c.issue}';

class _ReportCategoryScreenState extends State<ReportCategoryScreen> {
  // Tapping a pill picks it; Continue (per the frame) advances with it.
  CategoryChoice? _choice;
  String? _choiceKey;

  void _pick(String key, CategoryChoice choice) => setState(() {
        _choiceKey = key;
        _choice = choice;
      });

  // Branch D: the preview's category picker — the question and the scope
  // note, then one white card per category with its colour, the issues
  // as pills (the picked one fills with the category's colour), and Back
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
                _CategoryCard(category: c, selectedKey: _choiceKey, onPick: _pick),
                const SizedBox(height: 12),
              ],
              _OthersCard(selected: _choiceKey == _othersKey, onPick: _pick),
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

/// One category: its colour, its name, its issues as pills.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.selectedKey, required this.onPick});

  final ComplaintCategory category;
  final String? selectedKey;
  final void Function(String key, CategoryChoice choice) onPick;

  @override
  Widget build(BuildContext context) {
    final col = categoryColour(category);
    return _Shell(
      colour: col,
      title: category.label,
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final issue in category.issues)
          Builder(builder: (context) {
            final choice = CategoryChoice(category: category, issue: issue);
            final key = _keyOf(choice);
            return _IssuePill(label: issue, colour: col, selected: selectedKey == key, onTap: () => onPick(key, choice));
          }),
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
    final col = categoryColour(ComplaintCategory.other);
    return _Shell(
      colour: col,
      title: context.s.reportCategoryOthersHeading,
      child: _IssuePill(
        label: context.s.reportCategoryOthers,
        colour: col,
        selected: selected,
        // Its own category since 0076.
        onTap: () => onPick(_othersKey, const CategoryChoice(category: ComplaintCategory.other)),
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
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
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
                  fontFamily: 'Urbanist',
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
