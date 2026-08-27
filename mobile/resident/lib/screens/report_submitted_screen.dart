// SmartSumbong — Report submitted.
//
// Figma node 2547:84, with the copied state from 2853:174.
//
// The tracking ID is the only thing a resident has if they walk into the
// barangay hall to ask about their complaint, so it is the whole point
// of this screen: large, copyable, and confirmed when copied.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../theme.dart';

class ReportSubmittedScreen extends StatefulWidget {
  const ReportSubmittedScreen({super.key, required this.trackingId});

  final String? trackingId;

  @override
  State<ReportSubmittedScreen> createState() => _ReportSubmittedScreenState();
}

class _ReportSubmittedScreenState extends State<ReportSubmittedScreen> {
  bool _copied = false;

  Future<void> _copy() async {
    final id = widget.trackingId;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    setState(() => _copied = true);
    // Back to the copy affordance after a moment, so the screen does not
    // stay stuck in a state that is no longer news.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final id = widget.trackingId;

    return PopScope(
      // Back would return to the form they just submitted. Home is the
      // only sensible destination.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 43),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.reportSubmittedTitle,
                  textAlign: TextAlign.center,
                  style: t.headlineLarge?.copyWith(fontSize: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  s.reportSubmittedBody,
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(fontSize: 16, height: 1.25),
                ),
                const SizedBox(height: 45),

                if (id != null) _TicketCard(
                  trackingId: id,
                  copied: _copied,
                  onCopy: _copy,
                ),

                const SizedBox(height: 45),
                SizedBox(
                  width: 301,
                  child: FilledButton(
                    onPressed: _goHome,
                    child: Text(s.reportSubmittedBackHome),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goHome() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
}

/// The orange ticket stub, notched at both ends like a torn coupon.
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.trackingId,
    required this.copied,
    required this.onCopy,
  });

  final String trackingId;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 303,
      height: 95,
      child: CustomPaint(
        painter: _TicketPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trackingId,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: context.colors.bg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copied
                          ? context.s.reportSubmittedCopied
                          : context.s.reportSubmittedReferenceNumber,
                      style: TextStyle(fontSize: 12, color: context.colors.bg),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: Icon(
                  copied ? Icons.check : Icons.copy_rounded,
                  color: context.colors.bg,
                  size: 20,
                ),
                tooltip: context.s.reportSubmittedCopyTooltip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const notch = 10.0;
    final paint = Paint()..color = const Color(0xFFFF9800);

    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ));

    // Bite a semicircle out of each side, which is what makes it read as
    // a ticket rather than a card.
    final notches = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(0, size.height / 2), radius: notch))
      ..addOval(Rect.fromCircle(
          center: Offset(size.width, size.height / 2), radius: notch));

    canvas.drawPath(
      Path.combine(PathOperation.difference, body, notches),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
