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

import '../i18n.dart';
import '../theme.dart';
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

  String get _head => '(# ${widget.trackingId} - ${widget.statusLabel}) '
      '${widget.subject}';

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
      child: Scaffold(
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: _sent ? _confirmation() : _form(),
          ),
        ),
      ),
    );
  }

  // Figma TICKET ADDTL SUBMITTED: the 30/800 headline, the 16/500 thanks,
  // and the 301x44 navy Back to Home.
  Widget _confirmation() {
    final s = context.s;
    final c = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(43, figmaTop(context, 331, min: 40), 43, 24),
      child: Column(
        children: [
          Text(
            s.addDetailsSentTitle(_head),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w800,
              fontSize: 30,
              height: 1.0,
              color: c.navy,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            s.addDetailsSentBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              height: 20 / 16,
              color: c.navy,
            ),
          ),
          const SizedBox(height: 48),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 301),
            child: FigmaPill(
              onPressed: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (_) => false),
              child: Text(s.reportSubmittedBackHome),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    final s = context.s;
    final c = context.colors;
    final navy = c.navy;
    final created = widget.createdAt?.toLocal();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(41, figmaTop(context, 45, min: 16), 41, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The frame's navy header card: 20 radius, the ticket at
          // 28/800 on a 30 line, the date 12/500 under it.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 18, 17),
            decoration: BoxDecoration(
              color: const Color(0xFF00308F),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.addDetailsHeader(_head),
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    height: 30 / 28,
                    color: Color(0xFFF3F3F3),
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.addDetailsDateSubmitted(
                        '${s.monthFull(created.month)} ${created.day}, '
                        '${created.year}'),
                    style: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 15 / 12,
                      color: Color(0xFFF3F3F3),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 33),

          Text(
            s.addDetailsInstruction,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 18 / 16,
              color: navy,
            ),
          ),
          const SizedBox(height: 12),
          // The tanod's own question, in the design's orange-edged card.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: kFigmaOrange.withValues(alpha: 0.12),
              border: Border.all(color: kFigmaOrange),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: s.addDetailsQuestionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: widget.question),
              ]),
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.35,
                color: navy,
              ),
            ),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _details,
            enabled: !_busy,
            minLines: 5,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: navy,
            ),
            decoration: InputDecoration(
              hintText: s.addDetailsHint,
              hintStyle: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: navy,
              ),
              contentPadding: const EdgeInsets.fromLTRB(17, 12, 17, 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide(color: navy),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide(color: navy),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Align(
            alignment: Alignment.centerLeft,
            child: _photo == null
                ? _AttachTile(onTap: _busy ? null : _addPhoto)
                : _PhotoChip(
                    photo: _photo!,
                    onRemove: _busy ? null : () => setState(() => _photo = null),
                  ),
          ),
          const SizedBox(height: 30),

          // The frame's acknowledgement: a 12px box, the 12/400 line.
          InkWell(
            onTap: _busy
                ? null
                : () => setState(() {
                      _acknowledged = !_acknowledged;
                      _error = null;
                    }),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  checked: _acknowledged,
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4, right: 4),
                    decoration: BoxDecoration(
                      color: c.field,
                      border: Border.all(color: navy),
                    ),
                    child: _acknowledged
                        ? Icon(Icons.check, size: 10, color: navy)
                        : null,
                  ),
                ),
                Expanded(
                  child: Text(
                    s.reportDetailsAcknowledgement,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 18.72 / 12,
                      color: navy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: c.hint, fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 27),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: FigmaPill(
                    style: FigmaPillStyle.light,
                    height: 45,
                    onPressed:
                        _busy ? null : () => Navigator.of(context).maybePop(),
                    child: Text(s.reportsDialogBack),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: FigmaPill(
                    height: 45,
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.bg),
                          )
                        : Text(s.reportsSubmit),
                  ),
                ),
              ),
            ],
          ),
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
    final c = context.colors;
    final s = context.s;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: 174,
        height: 128,
        decoration: BoxDecoration(
          color: c.field,
          borderRadius: BorderRadius.circular(25),
        ),
        child: CustomPaint(
          painter: _Dashed(color: c.navy),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/icon-attach.png',
                  width: 20, height: 20, color: c.navy),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.reportsAttachMedia,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 14 / 12,
                        color: c.navy,
                      )),
                  Text(s.reportsMaxPhotoSize,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                        height: 1,
                        color: c.navy,
                      )),
                ],
              ),
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
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: c.navy),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.file(photo, width: 56, height: 56, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Text(
            context.s.reportsPhotoAttachedNote,
            style: TextStyle(fontSize: 12, color: c.navy),
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: c.navy),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  const _Dashed({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.5),
        const Radius.circular(25),
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
  bool shouldRepaint(covariant _Dashed oldDelegate) => oldDelegate.color != color;
}
