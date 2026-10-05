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

import 'legal_text.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';

class TermsPrivacyScreen extends StatefulWidget {
  const TermsPrivacyScreen({super.key});

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

// The team's final Terms and Conditions and Privacy Policy (legal_text.dart),
// one tab each, every section a numbered card that opens on tap.
class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  bool _privacy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final sections = _privacy ? privacySections : termsSections;
    Widget tab(String label, bool privacy) {
      final on = _privacy == privacy;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _privacy = privacy),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? d.btn : d.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? d.btn : d.line)),
            child: Text(label, textAlign: TextAlign.center, style: DType.body(on ? Colors.white : d.ink2, size: 13.5, w: FontWeight.w700)),
          ),
        ),
      );
    }

    return DPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Row(children: [
            const DBack(),
            const SizedBox(width: 10),
            Expanded(child: Text(s.termsPrivacyTitle, style: DType.h2(d.ink).copyWith(fontSize: 22))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            tab('Terms and Conditions', false),
            const SizedBox(width: 8),
            tab('Privacy Policy', true),
          ]),
          const SizedBox(height: 10),
          Text(legalEffective, style: DType.body(d.muted, size: 12.5, w: FontWeight.w600)),
          const SizedBox(height: 10),
          for (var i = 0; i < sections.length; i++) ...[
            _Acc(key: ValueKey('${_privacy}_$i'), n: i + 1, title: sections[i].$1, body: sections[i].$2),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Acc extends StatefulWidget {
  const _Acc({super.key, required this.n, required this.title, required this.body});

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
    // `.acc`: radius 16, the number in a 26 px rounded square tinted with
    // the role colour, the chevron turning as it opens.
    return DSheet(
      padding: EdgeInsets.zero,
      onTap: () => setState(() => _open = !_open),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Color.alphaBlend(d.link.withValues(alpha: .12), d.card)),
              child: Center(child: Text('${widget.n}', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, color: d.link))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.title, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800))),
            AnimatedRotation(
              turns: _open ? .25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text('›', style: TextStyle(fontSize: 20, height: 1, color: d.muted)),
            ),
          ]),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 14, 14),
            child: Text(widget.body, style: DType.body(d.ink2, size: 13).copyWith(height: 1.5)),
          ),
      ]),
    );
  }
}
