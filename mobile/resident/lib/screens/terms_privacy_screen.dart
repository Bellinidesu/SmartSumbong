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

import '../theme.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        surfaceTintColor: Tokens.bg,
        elevation: 0,
        foregroundColor: Tokens.navy,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
          children: [
            Center(
              child: Text('Terms & Privacy Notice',
                  style: t.headlineLarge?.copyWith(fontSize: 26)),
            ),
            const SizedBox(height: 16),
            _DraftBanner(),
            const SizedBox(height: 24),
            const _Section(
              title: 'Who is collecting your information',
              body:
                  'SmartSumbong is operated for Barangay 183, Pasay City, as '
                  'its local complaint-mapping system. For the purpose of the '
                  'Data Privacy Act of 2012 (RA 10173), the barangay is the '
                  'Personal Information Controller: it decides what this app '
                  'collects and why, and it is who to contact about your '
                  'data. The exact office and contact details a resident '
                  'should use go here once the barangay confirms them -- '
                  'this app currently only lists the barangay\'s Facebook '
                  'page in Settings.',
            ),
            const _Section(
              title: 'What we collect, and why',
              body:
                  '• Full name and mobile number, at sign-up -- your mobile '
                  'number is how you sign in, so it doubles as your account '
                  'identity.\n'
                  '• A photo of a government or barangay ID and a selfie, at '
                  'sign-up -- checked by a barangay officer before your '
                  'account is approved, so that reports in the system can be '
                  'traced to a real resident.\n'
                  '• Email address and home address -- both optional, and '
                  'editable any time in Edit Profile.\n'
                  '• A profile photo, if you choose to add one.\n'
                  '• Whatever you submit in a complaint report: category, '
                  'description, photos or a short video, and the map '
                  'location you place the pin at.\n'
                  '• A device token, used only to deliver push '
                  'notifications about your own reports and account.\n'
                  '• System records of your reports\' status changes, kept '
                  'as an accountability trail (who changed a report\'s '
                  'status and when) rather than as anything collected about '
                  'you directly.',
            ),
            const _Section(
              title: 'How your photos are handled',
              body:
                  'Every photo and video this app uploads -- ID, selfie, '
                  'profile photo, or report evidence -- has its metadata '
                  '(including GPS location embedded by your phone\'s camera) '
                  'stripped before it leaves your device, regardless of '
                  'whether you took it with the camera or picked it from '
                  'your gallery. The complaint\'s location comes only from '
                  'the map pin you place, never from a photo\'s hidden '
                  'metadata.',
            ),
            const _Section(
              title: 'Who can see it',
              body:
                  'Your identity documents are visible only to barangay '
                  'staff verifying your account. Report details are visible '
                  'to barangay staff and the tanod assigned to your report. '
                  'Other residents cannot see your name, contact details, or '
                  'ID -- and can file reports anonymously, in which case even '
                  'barangay staff see the report without your identity '
                  'attached. Nothing collected here is sold, or shared with '
                  'any organization outside the barangay\'s own operation of '
                  'this system.',
            ),
            const _Section(
              title: 'How it is stored',
              body:
                  'Data is stored in a Supabase-hosted database with '
                  'row-level security rules that limit each account to its '
                  'own records and role. Photos and videos are stored with '
                  'Cloudinary. Passwords are never visible to barangay staff '
                  'or stored by this app in plain form.',
            ),
            const _Section(
              title: 'How long we keep it',
              body:
                  'Account and report records are kept for as long as they '
                  'serve the barangay\'s record-keeping and accountability '
                  'purposes. A specific retention period, and the process '
                  'for a resident to request deletion of their account and '
                  'data, is something the barangay needs to set -- this app '
                  'does not yet have a self-service "delete my account" '
                  'action, and one should be added before or shortly after '
                  'this notice is finalised.',
            ),
            const _Section(
              title: 'Your rights',
              body:
                  'Under the Data Privacy Act, you may ask to access, '
                  'correct, or request deletion of your personal '
                  'information, object to its processing, and file a '
                  'complaint with the National Privacy Commission if you '
                  'believe it has been mishandled. Until a dedicated request '
                  'channel exists in this app, Personal Info and Phone '
                  'Number changes can already be requested from Edit '
                  'Profile, which notifies the barangay directly.',
            ),
            const _Section(
              title: 'Terms of use',
              body:
                  'This app is for reporting genuine barangay concerns. '
                  'Reports should be truthful and made in good faith; the '
                  'barangay may suspend an account it finds is being used to '
                  'file false, abusive, or repeatedly duplicate reports. '
                  'Your account\'s verification status, and any suspension, '
                  'is decided by barangay staff, not automatically by this '
                  'app.',
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
      child: const Text(
        'This is a draft prepared from how the app actually handles your '
        'data, for Barangay 183 to review, correct, and formally adopt. It '
        'is not yet an approved barangay document.',
        style: TextStyle(fontSize: 12, height: 1.4, color: Tokens.navy),
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
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 13, height: 1.45, color: Tokens.navy),
          ),
        ],
      ),
    );
  }
}
