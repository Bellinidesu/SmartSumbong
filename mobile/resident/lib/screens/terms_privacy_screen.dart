// SmartSumbong — Terms & Privacy Notice.
//
// Built during the Figma parity pass (27 Aug 2026), closing the gap the
// sign-up screen's own header comment flagged: "TODO: link these once
// the barangay's Terms and Privacy Notice exist." That TODO also names
// the reason this is not optional polish — collecting a government ID
// photo, a selfie, and a resident's complaint history makes a privacy
// notice naming the personal information controller a Republic Act
// 10173 (Data Privacy Act of 2012) requirement, not a formality. The
// Act requires a PIC to tell data subjects, before or at collection:
// who is collecting (the PIC), what is collected, why, who it is
// shared with, how long it is kept, and how to exercise their rights
// (access, correction, objection, deletion, complaint to the NPC).
//
// THIS IS A DRAFT, NOT THE BARANGAY'S APPROVED NOTICE. Every fact below
// is accurate to what this codebase actually does as of this migration
// (0038) and can be checked against it line for line -- it is not
// placeholder lorem ipsum, and it is not styled or worded to look like
// an already-finalised legal document. It is written so Barangay 183's
// actual officials (or whoever reviews this on their behalf) can read
// it, correct anything wrong, and adopt it -- or replace it outright --
// before this app reaches residents. The screen says as much at the
// top, in the same place a resident would see it, rather than only in
// this comment where they never would.
//
// This also doubles as the source text for the externally-hosted
// privacy policy URL that Google Play's Data Safety section requires
// at submission -- that page must live outside the app (a Play
// reviewer checks it without installing anything), so this in-app copy
// is necessary but not sufficient on its own; whoever publishes the
// Play listing still needs to host this (or the barangay's revision of
// it) somewhere reachable by URL and paste that URL into Play Console.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.bg,
        surfaceTintColor: context.colors.bg,
        elevation: 0,
        foregroundColor: context.colors.navy,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
          children: [
            Center(
              child: Text(s.termsPrivacyTitle,
                  style: t.headlineLarge?.copyWith(fontSize: 26)),
            ),
            const SizedBox(height: 16),
            const _DraftBanner(),
            const SizedBox(height: 24),
            _Section(
              title: s.termsPrivacySection1Title,
              body: s.termsPrivacySection1Body,
            ),
            _Section(
              title: s.termsPrivacySection2Title,
              body: s.termsPrivacySection2Body,
            ),
            _Section(
              title: s.termsPrivacySection3Title,
              body: s.termsPrivacySection3Body,
            ),
            _Section(
              title: s.termsPrivacySection4Title,
              body: s.termsPrivacySection4Body,
            ),
            _Section(
              title: s.termsPrivacySection5Title,
              body: s.termsPrivacySection5Body,
            ),
            _Section(
              title: s.termsPrivacySection6Title,
              body: s.termsPrivacySection6Body,
            ),
            _Section(
              title: s.termsPrivacySection7Title,
              body: s.termsPrivacySection7Body,
            ),
            _Section(
              title: s.termsPrivacySection8Title,
              body: s.termsPrivacySection8Body,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFFFF9800)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.s.termsPrivacyDraftBanner,
        style: TextStyle(fontSize: 12, height: 1.4, color: context.colors.navy),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(fontSize: 13, height: 1.45, color: context.colors.navy),
          ),
        ],
      ),
    );
  }
}
