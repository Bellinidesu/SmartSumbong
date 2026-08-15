// SmartSumbong — Submit Report, step 1: which category.
//
// Figma node 2212:145.

import 'package:flutter/material.dart';

import '../models/complaint_category.dart';
import '../theme.dart';

class ReportCategoryScreen extends StatelessWidget {
  const ReportCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(29, 32, 29, 16),
                children: [
                  Text(
                    'Which category most accurately reflects the issue?',
                    textAlign: TextAlign.center,
                    style: t.headlineLarge?.copyWith(fontSize: 26, height: 1.15),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select from the list below.',
                    textAlign: TextAlign.center,
                    style: t.titleMedium?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  // Straight from the design, and worth keeping verbatim:
                  // it is the line that keeps this system inside its
                  // scope. Katarungang Pambarangay mediation is not what
                  // this app does.
                  const Text(
                    '*Note: We do not interfere with the official '
                    'procedures, hearings, mediation, and settlement '
                    'processes. If the case is severe, it will be '
                    'escalated to proper authorities.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                      color: Color(0xFFFF4949),
                    ),
                  ),
                  const SizedBox(height: 24),

                  for (final c in ComplaintCategory.values) ...[
                    _CategoryCard(category: c),
                    const SizedBox(height: 20),
                  ],

                  _OthersCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(29, 0, 29, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Tokens.navy,
                        backgroundColor: Tokens.field,
                        minimumSize: const Size.fromHeight(45),
                        side: const BorderSide(color: Tokens.navy),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(19, 14, 19, 18),
      decoration: BoxDecoration(
        color: Tokens.navy,
        border: Border.all(color: Tokens.bg),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80121212),
            blurRadius: 2.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Tokens.bg,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
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
      decoration: BoxDecoration(
        color: Tokens.navy,
        border: Border.all(color: Tokens.bg),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80121212),
            blurRadius: 2.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'If the issue was not mentioned above:',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Tokens.bg,
            ),
          ),
          const SizedBox(height: 12),
          _IssuePill(
            label: 'Others',
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Tokens.field,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Tokens.navy,
          ),
        ),
      ),
    );
  }
}

void _choose(BuildContext context, CategoryChoice choice) {
  Navigator.of(context).pushNamed('/submit-report/details', arguments: choice);
}
