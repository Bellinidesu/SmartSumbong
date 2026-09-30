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

import '../i18n.dart';
import '../theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.navy,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.messagesTitle,
                style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: c.navy)),
            Text('${widget.trackingId} · ${widget.subject}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Urbanist', fontSize: 12.5, color: c.hint)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.navy))
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(s.messagesEmpty,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 14,
                                  height: 1.4,
                                  color: c.hint)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final mine = m['from_barangay'] != true;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * 0.78),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding:
                                  const EdgeInsets.fromLTRB(14, 9, 14, 8),
                              decoration: BoxDecoration(
                                color: mine ? c.navy : c.field,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(mine ? 18 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!mine)
                                    Text(s.messagesBarangay,
                                        style: const TextStyle(
                                          fontFamily: 'Urbanist',
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.5,
                                          color: Tokens.orange,
                                        )),
                                  Text(m['body'] as String? ?? '',
                                      style: TextStyle(
                                        fontFamily: 'Urbanist',
                                        fontSize: 14,
                                        height: 1.3,
                                        color: mine ? c.bg : c.navy,
                                      )),
                                  const SizedBox(height: 3),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(_time(m['created_at'] as String?),
                                        style: TextStyle(
                                          fontFamily: 'Urbanist',
                                          fontSize: 10.5,
                                          color: (mine ? c.bg : c.navy)
                                              .withValues(alpha: 0.7),
                                        )),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFFF4949))),
            ),
          if (widget.canWrite)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                            fontFamily: 'Urbanist', fontSize: 14, color: c.navy),
                        decoration: InputDecoration(
                          hintText: s.messagesHint,
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: c.field,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: c.navy,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : _send,
                        child: Padding(
                          padding: const EdgeInsets.all(11),
                          child: _sending
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: c.bg))
                              : Icon(Icons.send_rounded, color: c.bg, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
