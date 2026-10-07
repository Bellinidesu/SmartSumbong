// SmartSumbong — Ask the barangay (0072).
//
// A complaint's own question thread between the resident and the
// barangay, the way a buyer messages a seller about one order: the
// resident asks, the admin answers from the portal's case page, and both
// sides are notified. Live while open. The thread belongs to the
// complaint, so it is there for as long as the complaint is.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../models/complaint_category.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

class ReportMessagesScreen extends StatefulWidget {
  const ReportMessagesScreen({
    super.key,
    required this.reportId,
    required this.trackingId,
    required this.subject,
    this.canWrite = true,
    this.category,
  });

  /// The case's category, for the dot beside the ticket.
  final ComplaintCategory? category;

  final String reportId;
  final String trackingId;
  final String subject;

  /// False once the complaint is archived or cancelled: the thread stays
  /// readable, the composer goes.
  final bool canWrite;

  static Future<void> open(BuildContext context, ReportMessagesScreen screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  State<ReportMessagesScreen> createState() => _ReportMessagesScreenState();
}

class _ReportMessagesScreenState extends State<ReportMessagesScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  RealtimeChannel? _live;

  @override
  void initState() {
    super.initState();
    _load();
    _live = Supabase.instance.client.channel('report-messages-${widget.reportId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'report_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'report_id',
          value: widget.reportId,
        ),
        callback: (_) => _load(),
      )
      ..subscribe();
  }

  @override
  void dispose() {
    final ch = _live;
    if (ch != null) unawaited(Supabase.instance.client.removeChannel(ch));
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('report_messages')
          .select('id, from_barangay, body, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: true);
      if (!mounted) return;
      final grew = rows.length > _messages.length;
      setState(() {
        _messages = rows;
        _loading = false;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('post_report_message',
          params: {'p_report': widget.reportId, 'p_body': body});
      _text.clear();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = context.s.messagesSendFailed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final hm = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
    return '${context.s.monthFull(d.month).substring(0, 3)} ${d.day}, $hm';
  }

  // Branch D, 1:1 with the preview's Ask the barangay: the header (a 36 px
  // back button, the 17/800 title, a dot in the case's colour and the
  // ticket), the day label, bubbles (yours the blue gradient on the right
  // with a square corner, the barangay's a white card with its seal and
  // name) and the composer — a 44 px pill and an orange send.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final dotCol = widget.category == null ? DColors.brandNavy : categoryColour(widget.category!);
    final msgs = _messages;
    final children = <Widget>[];
    String? lastDay;
    final now = DateTime.now();
    for (final m in msgs) {
      final at = DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();
      if (at != null) {
        final key = '${at.year}-${at.month}-${at.day}';
        if (key != lastDay) {
          lastDay = key;
          final isToday = at.year == now.year && at.month == now.month && at.day == now.day;
          children.add(Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text((isToday ? context.tr('Today', 'Ngayon') : '${s.monthAbbr(at.month)} ${at.day}').toUpperCase(),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: .84, color: d.muted)),
            ),
          ));
        }
      }
      final mine = m['from_barangay'] != true;
      final fg = mine ? Colors.white : d.ink;
      children.add(Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width - 28) * .8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: mine ? LinearGradient(begin: const Alignment(-.5, -1), end: const Alignment(.5, 1), colors: d.tanod ? [d.card1, d.card2] : const [Color(0xFF0A3BA0), Color(0xFF00308F)]) : null,
            color: mine ? null : d.card,
            border: mine ? null : Border.all(color: d.line),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 6),
              bottomRight: Radius.circular(mine ? 6 : 18),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipOval(child: Image.asset('assets/images/brgy-183-seal.png', width: 16, height: 16)),
                  const SizedBox(width: 6),
                  Text(s.messagesBarangay, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 12, color: d.link)),
                ]),
              ),
            Text(m['body'] as String? ?? '', style: DType.body(fg, size: 14, w: FontWeight.w400).copyWith(height: 1.4)),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_time(m['created_at'] as String?), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 10.5, color: fg.withValues(alpha: .7))),
            ),
          ]),
        ),
      ));
      children.add(const SizedBox(height: 10));
    }

    return Scaffold(
      backgroundColor: d.bg,
      body: Stack(children: [
        const DContour(),
        SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.line))),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: d.card, shape: BoxShape.circle, border: Border.all(color: d.line)),
                    child: Icon(Icons.chevron_left_rounded, size: 24, color: d.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.messagesTitle, style: DType.body(d.ink, size: 17, w: FontWeight.w800).copyWith(height: 1.2)),
                    Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: dotCol)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${widget.trackingId} · ${widget.subject}', maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.muted, size: 12))),
                    ]),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: d.accent))
                  : msgs.isEmpty
                      ? Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), child: Text(s.messagesEmpty, textAlign: TextAlign.center, style: DType.body(d.muted, size: 13).copyWith(height: 1.45))))
                      : ListView(controller: _scroll, padding: const EdgeInsets.all(14), children: children),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
              ),
            if (widget.canWrite)
              Container(
                decoration: BoxDecoration(color: d.bg, border: Border(top: BorderSide(color: d.line))),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _text,
                        enabled: !_sending,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        style: DType.body(d.ink, size: 14, w: FontWeight.w400),
                        decoration: InputDecoration(
                          hintText: s.messagesHint,
                          hintStyle: DType.body(d.muted, size: 14, w: FontWeight.w400),
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: d.card,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: d.line)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: d.line)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: d.btn)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: DColors.orange, boxShadow: [BoxShadow(color: Color(0x4DFF9800), blurRadius: 12, offset: Offset(0, 4))]),
                      child: _sending
                          ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
