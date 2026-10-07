// SmartSumbong — send the tanod the more details they asked for.
//
// Figma: REPORTS - REQUIRE ADDTL, then TICKET ADDTL SUBMITTED.
//
// The tanod handling a report can ask the resident for more (0065's
// request_additional_details); the resident is notified, sees the
// question on the report, and answers here. The answer is text and/or
// one photo, sent through submit_additional_details, which files the
// photo with the report's evidence (same caps as any other) and tells
// the tanod.
//
// Laid out as the frame: the navy header card with the ticket and date,
// the frame's instruction line (with the tanod's own question under it,
// which the frame's placeholder text stands in for), the 128-tall box
// with its 0/500 count, the 174x128 Attach Media tile, the
// acknowledgement, and the 150x45 Back / Submit pair. Sending lands on
// the TICKET ADDTL SUBMITTED confirmation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_theme.dart';
import '../d/d_success.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../widgets/figma_ui.dart';

class AddDetailsScreen extends StatefulWidget {
  const AddDetailsScreen({
    super.key,
    required this.requestId,
    required this.trackingId,
    required this.subject,
    required this.statusLabel,
    required this.createdAt,
    required this.question,
    required this.uploader,
  });

  final String requestId;
  final String trackingId;
  final String subject;
  final String statusLabel;
  final DateTime? createdAt;
  final String question;
  final MediaUploader uploader;

  /// Opens the page; true once the details were sent.
  static Future<bool> open(BuildContext context, AddDetailsScreen screen) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    return sent == true;
  }

  @override
  State<AddDetailsScreen> createState() => _AddDetailsScreenState();
}

class _AddDetailsScreenState extends State<AddDetailsScreen> {
  final _details = TextEditingController();
  File? _photo;
  bool _acknowledged = false;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }


  Future<void> _addPhoto() async {
    final s = context.s;
    final source = await showFigmaSourceSheet(
      context,
      takeLabel: s.reportsTakePhoto,
      galleryLabel: s.reportsChooseFromGallery,
    );
    if (source == null || !mounted) return;
    final granted = await PermissionGate.ensure(
      context,
      permission: source == ImageSource.camera
          ? AppPermission.camera
          : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.reportsCameraAccessTitle
          : s.reportsPhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.reportsCameraAccessRationale
          : s.reportsPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null || !mounted) return;
      setState(() {
        _photo = f;
        _error = null;
      });
    } on MediaUploadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final s = context.s;
    final text = _details.text.trim();
    if (text.isEmpty && _photo == null) {
      setState(() => _error = s.addDetailsRequired);
      return;
    }
    if (!_acknowledged) {
      setState(() => _error = s.reportsAckRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final media = <Map<String, dynamic>>[];
      if (_photo != null) {
        final up =
            await widget.uploader.upload(_photo!, kind: MediaKind.reportPhoto);
        media.add(up.toJson());
      }
      await Supabase.instance.client.rpc('submit_additional_details', params: {
        'p_request': widget.requestId,
        'p_details': text.isEmpty ? null : text,
        'p_media': media,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        _busy = false;
        _error = m.contains('already been answered')
            ? s.addDetailsAlreadyAnswered
            : m.contains('no longer being worked on')
                ? s.addDetailsNoLongerOpen
                : m.contains('maximum')
                    ? s.addDetailsPhotoLimit
                    : s.addDetailsFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = s.addDetailsFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // After sending, Back means the same as the page's own button.
      canPop: !_sent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _sent) Navigator.of(context).pop(true);
      },
      child: DPage(
        fullContour: _sent,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: _sent ? _confirmation() : _form(),
        ),
      ),
    );
  }

  // Figma TICKET ADDTL SUBMITTED: the 30/800 headline, the 16/500 thanks,
  // and the 301x44 navy Back to Home.
  Widget _confirmation() {
    final s = context.s;
    // Ace (7 Oct 2026): the shared success page, blue ticket.
    return DSuccess(
      title: context.tr('Details sent', 'Naipadala ang detalye'),
      body: s.addDetailsSentBody,
      button: s.reportSubmittedBackHome,
      onButton: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
      ticketId: widget.trackingId,
      tone: DTicketTone.inProgress,
      status: context.tr('With the tanod', 'Nasa tanod'),
    );
  }

  // Branch D, 1:1 with the preview's Add details: a blue card with the
  // label, the report and a close; the ask; the tanod's question in amber;
  // the text box with its counter; the dashed attach tile; the
  // acknowledgement; Back and Submit.
  Widget _form() {
    final s = context.s;
    final d = context.d;
    final created = widget.createdAt?.toLocal();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const RadialGradient(center: Alignment(-.6, -.8), radius: 1.4, colors: [Color(0xFF7FA2FF), Color(0xFF356CF9), Color(0xFF1C47B8)], stops: [0, .6, 1]),
            ),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: Text(context.tr('ADD DETAILS', 'MAGDAGDAG NG DETALYE'),
                      style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 1.05, color: Colors.white70)),
                ),
                const SizedBox(height: 2),
                Text(widget.subject, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 19, height: 1.25, color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  '${widget.trackingId}${created == null ? '' : ' · ${s.addDetailsDateSubmitted('${s.monthFull(created.month)} ${created.day}, ${created.year}')}'}',
                  style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 12.5, color: Colors.white),
                ),
              ]),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: _busy ? null : () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x4D000000)),
                    child: const Icon(Icons.close_rounded, size: 17, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(s.addDetailsInstruction, style: DType.body(d.ink2, size: 13.5).copyWith(height: 1.45)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(const Color(0xFFF59E0B).withValues(alpha: .12), d.card),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.addDetailsQuestionLabel.trim(), style: DType.body(d.muted, size: 12, w: FontWeight.w800)),
              Text(widget.question, style: DType.body(d.ink, size: 13.5).copyWith(height: 1.45)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            enabled: !_busy,
            minLines: 5,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            style: DType.body(d.ink, size: 14),
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                Text('$currentLength/${maxLength ?? 500}', style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 11, color: d.muted)),
            decoration: InputDecoration(
              hintText: s.addDetailsHint,
              hintStyle: DType.body(d.muted, size: 14),
              filled: true,
              fillColor: d.card,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.link)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _photo == null
                ? _AttachTile(onTap: _busy ? null : _addPhoto)
                : _PhotoChip(photo: _photo!, onRemove: _busy ? null : () => setState(() => _photo = null)),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _busy
                ? null
                : () => setState(() {
                      _acknowledged = !_acknowledged;
                      _error = null;
                    }),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                checked: _acknowledged,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1, right: 8),
                  decoration: BoxDecoration(
                    color: _acknowledged ? d.btn : d.card,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _acknowledged ? d.btn : d.muted, width: 1.5),
                  ),
                  child: _acknowledged ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                ),
              ),
              Expanded(child: Text(s.reportDetailsAcknowledgement, style: DType.body(d.ink2, size: 12.5).copyWith(height: 1.4))),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: DButton(s.reportsDialogBack, kind: DButtonKind.ghost, expand: true, onTap: _busy ? null : () => Navigator.of(context).maybePop())),
            const SizedBox(width: 10),
            Expanded(child: DButton(s.reportsSubmit, expand: true, busy: _busy, onTap: _busy ? null : _submit)),
          ]),
        ],
      ),
    );
  }
}

/// The frame's 174x128 dashed Attach Media tile.
class _AttachTile extends StatelessWidget {
  const _AttachTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final s = context.s;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 164,
        height: 120,
        decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(14)),
        child: CustomPaint(
          painter: _Dashed(color: d.line.withValues(alpha: 1), radius: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 28, color: d.link),
              const SizedBox(height: 6),
              Text(s.reportsAttachMedia, style: DType.body(d.link, size: 12, w: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(s.reportsMaxPhotoSize, style: DType.body(d.muted, size: 10.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The attached photo, with a way to take it off again.
class _PhotoChip extends StatelessWidget {
  const _PhotoChip({required this.photo, required this.onRemove});

  final File photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: d.card, border: Border.all(color: d.line), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(photo, width: 56, height: 56, fit: BoxFit.cover)),
          const SizedBox(width: 10),
          Text(context.s.reportsPhotoAttachedNote, style: DType.body(d.ink2, size: 12)),
          IconButton(icon: Icon(Icons.cancel, color: d.muted), onPressed: onRemove),
        ],
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  const _Dashed({required this.color, this.radius = 25});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.5),
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + 6).clamp(0, metric.length)),
          paint,
        );
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Dashed oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
