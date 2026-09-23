// SmartSumbong — Submit Report, step 1: which category.
//
// Figma node 2212:145.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models/complaint_category.dart';
import '../theme.dart';

class ReportCategoryScreen extends StatelessWidget {
  const ReportCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    // Figma SUBMIT REPORT (2212:145): a white page (the theme's `field`,
    // #FBFBFB, so dark mode still has its own value), title block inset
    // 43, cards at x=29 and 20 apart, and the buttons at the end of the
    // scrolling page rather than pinned to the screen.
    return Scaffold(
      backgroundColor: context.colors.field,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(29, 26, 29, 50),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Text(
                    s.reportCategoryHeading,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      height: 30 / 28,
                      color: context.colors.navy,
                    ),
                  ),
                  Text(
                    s.reportCategorySubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      height: 1.2,
                      color: context.colors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Straight from the design, and worth keeping verbatim:
                  // it is the line that keeps this system inside its
                  // scope. Katarungang Pambarangay mediation is not what
                  // this app does.
                  Text(
                    s.reportCategoryNote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 15 / 12,
                      color: Color(0xFFFF4949),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            for (final c in ComplaintCategory.values) ...[
              _CategoryCard(category: c),
              const SizedBox(height: 20),
            ],

            _OthersCard(),
            const SizedBox(height: 32),

            // The frame pairs Back with a Continue; this screen has none
            // because tapping an issue already advances (see
            // _CategoryCard), so Back sits centred where the pair was.
            Center(
              child: SizedBox(
                width: 150,
                height: 45,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D121212),
                        blurRadius: 3.5,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.navy,
                      backgroundColor: context.colors.field,
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: context.colors.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    child: Text(s.reportCategoryBack),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame's navy card: 353 wide, radius 25, 20/15 padding, a 1px
/// #F3F3F3 edge and a y5 / blur 5 shadow at 50%.
BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: context.colors.navy,
      border: Border.all(color: context.colors.bg),
      borderRadius: BorderRadius.circular(25),
      boxShadow: const [
        BoxShadow(
          color: Color(0x80121212),
          blurRadius: 3.5,
          offset: Offset(0, 5),
        ),
      ],
    );

TextStyle _cardHeading(BuildContext context) => TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 14,
      height: 21.84 / 14,
      color: context.colors.bg,
    );

/// One navy card: the group heading, then its issues as pills.
///
/// The design lays the pills out at fixed positions; a Wrap is used here
/// so they reflow on a narrower handset instead of clipping. Tapping a
/// pill selects and advances — there is no separate Continue, because
/// choosing the issue *is* the choice.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category});

  final ComplaintCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.label, style: _cardHeading(context)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final issue in category.issues)
                _IssuePill(
                  label: issue,
                  onTap: () => _choose(
                    context,
                    CategoryChoice(category: category, issue: issue),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OthersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.reportCategoryOthersHeading,
            style: _cardHeading(context),
          ),
          const SizedBox(height: 5),
          _IssuePill(
            label: context.s.reportCategoryOthers,
            onTap: () => _choose(
              context,
              // No enum value for "Others". Peace, Order & Nuisance is
              // the closest general bucket and an admin can recategorise
              // — but this is a gap between the design and the schema,
              // and it should go to Rose and the adviser rather than
              // stay a silent decision.
              const CategoryChoice(
                category: ComplaintCategory.peaceOrderNuisance,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame's pill: 30 tall, radius 20, #FBFBFB, 12/500 navy text,
/// as wide as its label. No `alignment` on the Container — that made
/// every pill fill the card's width.
class _IssuePill extends StatelessWidget {
  const _IssuePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.colors.field,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: context.colors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

void _choose(BuildContext context, CategoryChoice choice) {
  Navigator.of(context).pushNamed('/submit-report/details', arguments: choice);
}
