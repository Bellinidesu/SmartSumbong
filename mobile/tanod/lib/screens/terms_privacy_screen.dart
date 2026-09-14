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

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                s.termsPrivacyTitle,
                textAlign: TextAlign.center,
                style: t.headlineLarge?.copyWith(fontSize: 22),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                s.termsPrivacySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.muted),
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
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: c.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: TextStyle(
                            fontSize: 13, height: 1.5, color: c.navy),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: Text(s.termsPrivacyBack),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
