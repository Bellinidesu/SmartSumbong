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
import '../d/d_theme.dart';
import '../d/d_ui.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  // No frame of its own: set like the translated pages — the title
  // 28/800 at 50 (no app bar; the pill at the foot and the system back
  // both return), 16/700 headings over 14/500 text, and the 150x45 Back.
  // Branch D: back, the heading, the draft note, then the eight sections
  // as numbered cards that open one at a time.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final sections = [
      (s.termsPrivacySection1Title, s.termsPrivacySection1Body),
      (s.termsPrivacySection2Title, s.termsPrivacySection2Body),
      (s.termsPrivacySection3Title, s.termsPrivacySection3Body),
      (s.termsPrivacySection4Title, s.termsPrivacySection4Body),
      (s.termsPrivacySection5Title, s.termsPrivacySection5Body),
      (s.termsPrivacySection6Title, s.termsPrivacySection6Body),
      (s.termsPrivacySection7Title, s.termsPrivacySection7Body),
      (s.termsPrivacySection8Title, s.termsPrivacySection8Body),
    ];
    return DPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          const Align(alignment: Alignment.centerLeft, child: DBack()),
          const SizedBox(height: 12),
          DHeading(s.termsPrivacyTitle),
          const SizedBox(height: 14),
          const _DraftBanner(),
          const SizedBox(height: 14),
          for (var i = 0; i < sections.length; i++) ...[
            _Acc(n: i + 1, title: sections[i].$1, body: sections[i].$2),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Acc extends StatefulWidget {
  const _Acc({required this.n, required this.title, required this.body});

  final int n;
  final String title;
  final String body;

  @override
  State<_Acc> createState() => _AccState();
}

class _AccState extends State<_Acc> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return DSheet(
      padding: EdgeInsets.zero,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: d.field, border: Border.all(color: d.line)),
              child: Center(child: Text('${widget.n}', style: DType.mono(d.link, size: 13))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.title, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800))),
            AnimatedRotation(
              turns: _open ? .25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.chevron_right_rounded, color: d.muted),
            ),
          ]),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 6, 2),
              child: Text(widget.body, style: DType.body(d.ink2, size: 13.5)),
            ),
        ]),
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: DColors.orange.withValues(alpha: 0.12),
        border: Border.all(color: DColors.orange),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        context.s.termsPrivacyDraftBanner,
        style: TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          height: 1.4,
          color: context.colors.navy,
        ),
      ),
    );
  }
}

