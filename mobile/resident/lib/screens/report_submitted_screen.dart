// SmartSumbong — Report submitted.
//
// Figma node 2547:84, with REPORTED - TICKET COPIED as the popup.
//
// The tracking ID is the only thing a resident has if they walk into the
// barangay hall to ask about their complaint, so it is the whole point
// of this screen: large, copyable, and confirmed when copied.

import 'package:flutter/material.dart';

import '../d/d_success.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

class ReportSubmittedScreen extends StatefulWidget {
  const ReportSubmittedScreen({super.key, required this.trackingId});

  final String? trackingId;

  @override
  State<ReportSubmittedScreen> createState() => _ReportSubmittedScreenState();
}

class _ReportSubmittedScreenState extends State<ReportSubmittedScreen> {

  // Branch D: a green tick with a soft glow, the thank-you, the ticket
  // number on a role-colour card with Copy, and Back to Home.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final id = widget.trackingId;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: DPage(
        fullContour: true,
        child: DSuccess(
          title: s.reportSubmittedTitle,
          body: s.reportSubmittedBody,
          button: s.reportSubmittedBackHome,
          onButton: _goHome,
          ticketId: id,
          tone: DTicketTone.underReview,
          status: context.tr('Under Review', 'Nirerepaso'),
        ),
      ),
    );
  }

  void _goHome() => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
}

