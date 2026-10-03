// SmartSumbong — Report submitted.
//
// Figma node 2547:84, with REPORTED - TICKET COPIED as the popup.
//
// The tracking ID is the only thing a resident has if they walk into the
// barangay hall to ask about their complaint, so it is the whole point
// of this screen: large, copyable, and confirmed when copied.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

class ReportSubmittedScreen extends StatefulWidget {
  const ReportSubmittedScreen({super.key, required this.trackingId});

  final String? trackingId;

  @override
  State<ReportSubmittedScreen> createState() => _ReportSubmittedScreenState();
}

class _ReportSubmittedScreenState extends State<ReportSubmittedScreen> {
  Future<void> _copy() async {
    final id = widget.trackingId;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('$id copied', 'Nakopya ang $id'))));
  }

  // Branch D: a green tick with a soft glow, the thank-you, the ticket
  // number on a role-colour card with Copy, and Back to Home.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final id = widget.trackingId;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: DPage(
        fullContour: true,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DColors.greenVivid,
                      boxShadow: [BoxShadow(color: DColors.greenVivid.withValues(alpha: .45), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    child: const Icon(Icons.check_rounded, size: 56, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 22),
                Text(s.reportSubmittedTitle, textAlign: TextAlign.center, style: DType.h1(d.accent).copyWith(fontSize: 28)),
                const SizedBox(height: 6),
                Text(s.reportSubmittedBody, textAlign: TextAlign.center, style: DType.body(d.muted, size: 15)),
                const SizedBox(height: 26),
                if (id != null)
                  DCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.tr('YOUR TICKET', 'IYONG TICKET'), style: DType.label(Colors.white.withValues(alpha: .75))),
                          const SizedBox(height: 4),
                          Text(id, style: DType.mono(Colors.white, size: 22)),
                        ]),
                      ),
                      IconButton(
                        onPressed: _copy,
                        tooltip: context.tr('Copy', 'Kopyahin'),
                        icon: const Icon(Icons.content_copy_rounded, color: Colors.white),
                      ),
                    ]),
                  ),
                const SizedBox(height: 26),
                DButton(s.reportSubmittedBackHome, expand: true, onTap: _goHome),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _goHome() => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
}

