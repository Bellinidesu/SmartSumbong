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
    final s = context.s;
    final id = widget.trackingId;

    return PopScope(
      // Back would return to the form they just submitted. Home is the
      // only sensible destination.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      // Figma REPORTED (2547:84): the block starts 213 from the top of
      // the screen (not vertically centred), title 30/800 with the body
      // 4 under it, then the ticket and the button 45 apart. Scrolls on
      // a short screen rather than overflowing.
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              43,
              (213 - MediaQuery.paddingOf(context).top).clamp(24.0, 213.0),
              43,
              24,
            ),
            children: [
              Text(
                s.reportSubmittedTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: 38 / 30,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.reportSubmittedBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 20 / 16,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 45),

              if (id != null)
                Center(
                  child: _TicketCard(
                    trackingId: id,
                    copied: _copied,
                    onCopy: _copy,
                  ),
                ),

              const SizedBox(height: 45),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D121212),
                        blurRadius: 3.5,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: _goHome,
                    style: FilledButton.styleFrom(
                      fixedSize: const Size(301, 44),
                      minimumSize: const Size(301, 44),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      side: BorderSide(color: context.colors.bg),
                    ),
                    child: Text(s.reportSubmittedBackHome),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goHome() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
}

/// The orange ticket stub, notched at both ends like a torn coupon.
///
/// Figma "ticket" (303x95 overall): a 277-wide orange body, radius 20,
/// inset 13 each side, with a 26x23 notch centred on each end. The ID
/// (16/700) and its label (12/500, 17 lower) start 45 into the body; the
/// frame's own 18px copy glyph sits 224 in.
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
        child: Stack(
          children: [
            Positioned(
              left: 58,
              right: 70,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trackingId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 17 / 16,
                      color: context.colors.bg,
                    ),
                  ),
                  Text(
                    copied
                        ? context.s.reportSubmittedCopied
                        : context.s.reportSubmittedReferenceNumber,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 18.72 / 12,
                      color: context.colors.bg,
                    ),
                  ),
                ],
              ),
            ),
            // A 48x48 tap target centred on the frame's 18x18 glyph
            // (224..242 across, 36..54 down).
            Positioned(
              left: 233 - 24,
              top: 45 - 24,
              width: 48,
              height: 48,
              child: IconButton(
                onPressed: onCopy,
                padding: EdgeInsets.zero,
                tooltip: context.s.reportSubmittedCopyTooltip,
                icon: copied
                    ? Icon(Icons.check, color: context.colors.bg, size: 18)
                    : CustomPaint(
                        size: const Size(18, 18),
                        painter: _CopyGlyphPainter(context.colors.bg),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 13.0;
    final paint = Paint()..color = const Color(0xFFFF9800);

    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, 0, size.width - 2 * inset, size.height),
        const Radius.circular(20),
      ));

    // A 26x23 bite centred on each end of the body, which is what makes
    // it read as a ticket rather than a card.
    final notches = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(inset, size.height / 2), width: 26, height: 23))
      ..addOval(Rect.fromCenter(
          center: Offset(size.width - inset, size.height / 2),
          width: 26,
          height: 23));

    canvas.drawPath(
      Path.combine(PathOperation.difference, body, notches),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The frame's copy glyph (Group 2: two 14x14 outlines, 2px stroke): a
/// rounded square in front and, behind it, just the top and left edges
/// of a second one. Drawn rather than bundled, so it stays sharp at
/// every density.
class _CopyGlyphPainter extends CustomPainter {
  _CopyGlyphPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromLTRBR(5, 5, 17, 17, const Radius.circular(2.5)),
      pen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(1, 13)
        ..lineTo(1, 3.5)
        ..arcToPoint(const Offset(3.5, 1), radius: const Radius.circular(2.5))
        ..lineTo(13, 1),
      pen,
    );
  }

  @override
  bool shouldRepaint(covariant _CopyGlyphPainter old) => old.colour != colour;
}
