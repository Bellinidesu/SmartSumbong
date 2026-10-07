// SmartSumbong — one success page for the whole app (Ace, 7 Oct 2026).
//
// Report submitted, Sent for approval and Details sent share it: the green
// tick with its glow, the title, the words, the ticket and one button, on
// the contour background. The ticket is the Figma ticket: notched on both
// sides with a perforated line between the number and its stub, coloured
// by where the case is (amber under review, blue in progress, violet
// waiting for the barangay's approval).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'd_theme.dart';
import 'd_ui.dart';

/// The ticket's colour for each moment, from the portal's status families.
class DTicketTone {
  const DTicketTone._(this.colour);
  final Color colour;

  static const underReview = DTicketTone._(Color(0xFFD97706));
  static const inProgress = DTicketTone._(Color(0xFF2F5FE0));
  static const awaitingApproval = DTicketTone._(Color(0xFF7C4DDB));
  static const done = DTicketTone._(Color(0xFF1F8A45));
}

class DTicket extends StatelessWidget {
  const DTicket({super.key, required this.id, required this.tone, required this.status, this.label});

  final String id;
  final DTicketTone tone;
  final String status;
  final String? label;

  static const _notch = 11.0;
  static const _stub = 46.0;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('$id copied', 'Nakopya ang $id'))));
  }

  @override
  Widget build(BuildContext context) {
    final c = tone.colour;
    final deep = Color.lerp(c, Colors.black, .28)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: c.withValues(alpha: .35), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: ClipPath(
        clipper: _TicketClipper(notch: _notch, stubHeight: _stub),
        child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, deep])),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label ?? context.tr('YOUR TICKET', 'IYONG TICKET'), style: DType.label(Colors.white.withValues(alpha: .8))),
                    const SizedBox(height: 4),
                    Text(id, style: DType.mono(Colors.white, size: 22)),
                  ]),
                ),
                IconButton(
                  onPressed: () => _copy(context),
                  tooltip: context.tr('Copy', 'Kopyahin'),
                  icon: const Icon(Icons.content_copy_rounded, color: Colors.white),
                ),
              ]),
            ),
            // the perforation between the notches
            SizedBox(
              height: 1.5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _notch + 6),
                child: LayoutBuilder(builder: (context, box) {
                  final n = (box.maxWidth / 9).floor();
                  return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    for (var i = 0; i < n; i++) Container(width: 5, height: 1.5, color: Colors.white.withValues(alpha: .45)),
                  ]);
                }),
              ),
            ),
            SizedBox(
              height: _stub,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status, style: DType.body(Colors.white, size: 13.5, w: FontWeight.w800))),
                  Text('SmartSumbong', style: DType.label(Colors.white.withValues(alpha: .6))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  _TicketClipper({required this.notch, required this.stubHeight});

  final double notch;
  final double stubHeight;

  @override
  Path getClip(Size size) {
    final y = size.height - stubHeight;
    final card = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: notch));
    return Path.combine(PathOperation.difference, card, holes);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.notch != notch || old.stubHeight != stubHeight;
}

/// The page's content: tick, title, words, ticket, button. Centred.
class DSuccess extends StatelessWidget {
  const DSuccess({
    super.key,
    required this.title,
    required this.body,
    required this.button,
    required this.onButton,
    this.ticketId,
    this.tone = DTicketTone.underReview,
    this.status = '',
  });

  final String title;
  final String body;
  final String button;
  final VoidCallback onButton;
  final String? ticketId;
  final DTicketTone tone;
  final String status;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return LayoutBuilder(
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
            Text(title, textAlign: TextAlign.center, style: DType.h1(d.accent).copyWith(fontSize: 28)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: DType.body(d.muted, size: 15)),
            const SizedBox(height: 26),
            if (ticketId != null) ...[
              DTicket(id: ticketId!, tone: tone, status: status),
              const SizedBox(height: 26),
            ],
            DButton(button, expand: true, onTap: onButton),
          ]),
        ),
      ),
    );
  }
}

/// The success as its own page, for a moment that used to be a popup.
Future<void> showDSuccessPage(
  BuildContext context, {
  required String title,
  required String body,
  required String button,
  String? ticketId,
  DTicketTone tone = DTicketTone.underReview,
  String status = '',
}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (ctx) => DPage(
        fullContour: true,
        child: DSuccess(
          title: title,
          body: body,
          button: button,
          onButton: () => Navigator.of(ctx).pop(),
          ticketId: ticketId,
          tone: tone,
          status: status,
        ),
      ),
    ));
