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

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

class ReportMessagesScreen extends StatefulWidget {
  const ReportMessagesScreen({
    super.key,
    required this.reportId,
    required this.trackingId,
    required this.subject,
    this.canWrite = true,
  });

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
          .order('created_at');
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

  // Branch D: back and the case at the top, the thread as bubbles (yours
  // in the role colour on the right, the barangay's white on the left with
  // its name in orange), the composer pinned with an orange send.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    return Scaffold(
      backgroundColor: d.bg,
      body: Stack(children: [
        const DContour(),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(children: [
                const DBack(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.messagesTitle, style: DType.h3(d.accent).copyWith(fontSize: 18)),
                    Text('${widget.trackingId} · ${widget.subject}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.muted, size: 12.5)),
                  ]),
                ),
              ]),
            ),
            Divider(height: 1, color: d.line),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: d.accent))
                  : _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const DWell(Icons.forum_outlined, size: 64),
                              const SizedBox(height: 12),
                              Text(s.messagesEmpty, textAlign: TextAlign.center, style: DType.body(d.muted, size: 14)),
                            ]),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final mine = m['from_barangay'] != true;
                            final fg = mine ? Colors.white : d.ink;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                                decoration: BoxDecoration(
                                  color: mine ? (d.tanod ? d.card1 : DColors.brandNavy) : d.card,
                                  border: mine ? null : Border.all(color: d.line),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(mine ? 18 : 4),
                                    bottomRight: Radius.circular(mine ? 4 : 18),
                                  ),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (!mine)
                                    Text(s.messagesBarangay,
                                        style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFE07400))),
                                  Text(m['body'] as String? ?? '', style: DType.body(fg, size: 14.5)),
                                  const SizedBox(height: 3),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(_time(m['created_at'] as String?), style: DType.body(fg.withValues(alpha: .7), size: 10.5)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
              ),
            if (widget.canWrite)
              Container(
                decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      style: DType.body(d.ink, size: 14.5),
                      decoration: InputDecoration(
                        hintText: s.messagesHint,
                        hintStyle: DType.body(d.muted, size: 14),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: d.field,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: d.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: d.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: DColors.orange, width: 1.6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: DColors.orange,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _send,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF141B34)))
                              : const Icon(Icons.send_rounded, color: Color(0xFF141B34), size: 21),
                        ),
                      ),
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
