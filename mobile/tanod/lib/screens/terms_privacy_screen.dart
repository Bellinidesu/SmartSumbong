// SmartSumbong — Terms & Privacy (tanod).
//
// Not the resident app's Terms & Privacy screen with a find-and-replace
// — service personnel have data the resident version never mentions
// (duty-time location, dispatch records, how a tanod's service ends),
// so this is its own drafted text. See the project note written
// alongside this screen for the reasoning behind each section.
//
// DRAFT: written for the barangay to review, not legal text vetted by
// counsel. If anything here changes before the defense or before real
// deployment, only i18n.dart's termsPrivacySections needs editing —
// this screen just renders whatever that list contains.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.s;

    // No frame of its own; in the frames' language: the title 28/800 at
    // y=50, 16/700 headings over 14/500 body, the 150x45 Back.
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: figmaTop(context, 50)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FigmaTitle(s.termsPrivacyTitle),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                s.termsPrivacySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: c.muted,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                itemCount: s.termsPrivacySections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (_, i) {
                  final (heading, body) = s.termsPrivacySections[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                          color: c.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 1.45,
                          color: c.navy,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
              child: FigmaBackPill(label: s.termsPrivacyBack),
            ),
          ],
        ),
      ),
    );
  }
}
