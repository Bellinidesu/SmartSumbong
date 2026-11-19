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
import '../widgets/category_card.dart';
import '../widgets/d_form.dart';
import 'where_screen.dart';

class ReportCategoryScreen extends StatefulWidget {
  const ReportCategoryScreen({super.key});

  @override
  State<ReportCategoryScreen> createState() => _ReportCategoryScreenState();
}

class _ReportCategoryScreenState extends State<ReportCategoryScreen> {
  /// A report keeps to one category (0176) and to three concerns (the database takes four; the form keeps to three).
  /// The concerns are the category's own pills, tapped in any number: the first one tapped is the main concern, the
  /// rest ride with it (Rose, 19 Nov 2026: no "add another" step when they can just be picked from the list).
  static const _maxConcerns = maxConcerns;

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

  /// The picks, shared with the steps after this one: "Your complaints" there changes them, and See all categories
  /// comes back here to the same ones.
  ValueNotifier<CategoryChoice>? _flow;

  void _fromFlow() {
    final v = _flow?.value;
    if (v == null || !mounted) return;
    setState(() {
      _category = v.category;
      _picked
        ..clear()
        ..addAll(v.concernOptions);
    });
  }

  @override
  void dispose() {
    _flow?.dispose();
    super.dispose();
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
      final next = toggleConcern(_picked, o, max: _maxConcerns);
      _picked
        ..clear()
        ..addAll(next);
      if (_picked.isEmpty) _category = null;
    });
  }

  Future<void> _pickOthers() async {
    if (_othersPicked || !await _leaveCategory(ComplaintCategory.other)) return;
    setState(() {
      _category = ComplaintCategory.other;
      _picked.clear();
    });
  }

  /// Continue: the second step, Where is it?, with the picks shared so the steps after can change them.
  void _choose(CategoryChoice choice) {
    _flow?.dispose();
    _flow = ValueNotifier<CategoryChoice>(choice)..addListener(_fromFlow);
    Navigator.of(context).pushNamed('/submit-report/where', arguments: WhereArgs(choice, picks: _flow));
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
      bottomBar: DFormBar(
        backLabel: s.reportCategoryBack,
        onBack: () => Navigator.of(context).pop(),
        okLabel: s.reportCategoryContinue,
        onOk: _choice == null ? null : () => _choose(_choice!),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Row(children: [const DFormBack(), const Spacer(), DStepChip(context.tr('Step 1 of 3', 'Hakbang 1 ng 3'))]),
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
            CategoryCard(
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
    return CategoryShell(
      colour: col,
      title: context.s.reportCategoryOthersHeading,
      child: ConcernPill(
        label: context.s.reportCategoryOthers,
        colour: col,
        selected: selected,
        // Its own category since 0076.
        onTap: onPick,
      ),
    );
  }
}



