// SmartSumbong — Ask the barangay (0072).
//
// A complaint's own question thread between the resident and the
// barangay, the way a buyer messages a seller about one order: the
// resident asks, the admin answers from the portal's case page, and both
// sides are notified. Live while open. The thread belongs to the
// complaint, so it is there for as long as the complaint is.
//
// 19 Nov 2026: this is the portal's Case chat on a phone (canvas frame R2): graphite and grey bubbles with the tail on the
// last bubble of a run, the day in bold, a pill field and a blue arrow. When the resident has asked for a reopen or an appeal,
// the thread opens with that request as a system card, and the status sits in a band under the header.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../models/complaint_category.dart';
import '../i18n.dart';
import 'case/case_ui.dart';

class ReportMessagesScreen extends StatefulWidget {
  const ReportMessagesScreen({
    super.key,
    required this.reportId,
    required this.trackingId,
    required this.subject,
    this.canWrite = true,
    this.category,
    this.status,
    this.request,
  });

  /// The case's category (kept for callers that pass it).
  final ComplaintCategory? category;

  final String reportId;
  final String trackingId;
  final String subject;

  /// False once the complaint is archived or cancelled: the thread stays
  /// readable, the composer goes.
  final bool canWrite;

  /// The case's status as the band under the header shows it: the label and the pill's colour.
  final (String, Color)? status;

  /// A reopen or an appeal the resident made, shown as the thread's first card: what they asked, the reason and when.
  final ({String title, String? reason, DateTime? at})? request;

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

  String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Today 9:41 AM", "Nov 18 3:40 PM": the day in bold, then the time.
  Widget _stamp(DateTime at, Color ink, Color sub) {
    final now = DateTime.now();
    final isToday = at.year == now.year && at.month == now.month && at.day == now.day;
    final day = isToday ? context.tr('Today', 'Ngayon') : '${context.s.monthAbbr(at.month)} ${at.day}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: day, style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
          TextSpan(text: ' ${_clock(at)}'),
        ]), style: caseInter(sub, 12, FontWeight.w500, 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final dark = context.d.dark;
    final bg = dark ? const Color(0xFF101215) : const Color(0xFFEEF2FA);
    final ink = dark ? const Color(0xFFF1F3F7) : const Color(0xFF171A20);
    final sub = dark ? const Color(0xFFA4AAB6) : const Color(0xFF5F6673);
    final hair = dark ? const Color(0x4778809F) : const Color(0x2E3C3C43);
    final fieldFill = dark ? const Color(0x3D767680) : const Color(0x1F767680);
    final blue = dark ? const Color(0xFF6EA0FF) : const Color(0xFF2F6BFF);
    final outBg = dark ? const Color(0xFF454B56) : const Color(0xFF2E333C);
    final inBg = dark ? const Color(0xFF2D3037) : const Color(0xFFECEEF2);
    final msgs = _messages;
    final children = <Widget>[];

    // the request the resident made opens the thread
    final req = widget.request;
    if (req != null) {
      if (req.at != null) children.add(_stamp(req.at!.toLocal(), ink, sub));
      children.add(Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF121417) : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: dark ? const Color(0x4778809F) : const Color(0x243C3C43)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 34, height: 34, decoration: const BoxDecoration(color: DStatusPill.violet, shape: BoxShape.circle), child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(req.title, style: caseInter(ink, 14, FontWeight.w700, 19)),
              if (req.reason != null) Text(context.tr('Reason: ${req.reason}', 'Dahilan: ${req.reason}'), style: caseInter(ink, 13.5, FontWeight.w500).copyWith(height: 1.45)),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(context.tr('The barangay has been told. You can chat here.', 'Nasabihan na ang barangay. Puwede kang mag-chat dito.'), style: caseInter(sub, 12.5, FontWeight.w500, 17)),
              ),
            ]),
          ),
        ]),
      ));
      children.add(const SizedBox(height: 10));
    }

    // the messages, in runs: the tail (a square corner) on the last bubble of a run
    DateTime? lastAt;
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final at = DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();
      if (at != null && (lastAt == null || at.difference(lastAt).inMinutes > 30 || at.day != lastAt.day)) {
        children.add(_stamp(at, ink, sub));
      }
      if (at != null) lastAt = at;
      final mine = m['from_barangay'] != true;
      final nextSame = i + 1 < msgs.length && (msgs[i + 1]['from_barangay'] != true) == mine;
      final prevSame = i > 0 && (msgs[i - 1]['from_barangay'] != true) == mine;
      const big = Radius.circular(18);
      const tail = Radius.circular(4);
      children.add(Padding(
        padding: EdgeInsets.only(top: prevSame ? 0 : 8, bottom: 3),
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? outBg : inBg,
              borderRadius: BorderRadius.only(
                topLeft: big,
                topRight: big,
                bottomLeft: !mine && !nextSame ? tail : big,
                bottomRight: mine && !nextSame ? tail : big,
              ),
            ),
            child: Text(m['body'] as String? ?? '', style: caseInter(mine ? Colors.white : ink, 15, FontWeight.w500).copyWith(height: 1.35)),
          ),
        ),
      ));
      if (mine && !nextSame && i == msgs.length - 1) {
        children.add(Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 0), child: Text(context.tr('Delivered', 'Naihatid'), style: caseInter(sub, 11.5, FontWeight.w500, 14)))));
      }
    }

    final st = widget.status;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [
          // header: back, the barangay's seal and name
          SizedBox(
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              Positioned(
                left: 10,
                child: Semantics(
                  button: true,
                  label: context.tr('Back', 'Bumalik'),
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: SizedBox(width: 44, height: 44, child: Icon(Icons.chevron_left_rounded, size: 30, color: ink)),
                    ),
                  ),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 36, height: 36, decoration: const BoxDecoration(color: CaseTokens.orange, shape: BoxShape.circle), child: const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF141B34))),
                const SizedBox(height: 2),
                Text(s.messagesBarangay, style: caseInter(ink, 13, FontWeight.w700, 16)),
              ]),
            ]),
          ),
          // the band: the status and which report this is
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: hair, width: .5), bottom: BorderSide(color: hair, width: .5))),
            child: Row(children: [
              if (st != null) ...[DStatusPill(st.$1, st.$2), const SizedBox(width: 10)],
              Expanded(child: Text('${widget.trackingId} · ${widget.subject}', maxLines: 1, overflow: TextOverflow.ellipsis, style: caseInter(sub, 12.5, FontWeight.w500, 17))),
            ]),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: context.d.accent))
                : (msgs.isEmpty && req == null)
                    ? Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Text(s.messagesEmpty, textAlign: TextAlign.center, style: caseInter(sub, 13.5, FontWeight.w500).copyWith(height: 1.45))))
                    : ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 6, 14, 14), children: children),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(_error!, style: caseInter(dark ? const Color(0xFFFF8A8A) : const Color(0xFFC4172A), 12.5, FontWeight.w700)),
            ),
          if (widget.canWrite)
            Container(
              decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: hair, width: .5))),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(color: fieldFill, borderRadius: BorderRadius.circular(22)),
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: caseInter(ink, 16, FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: s.messagesHint,
                        hintStyle: caseInter(sub, 16, FontWeight.w500),
                        counterText: '',
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: context.tr('Send', 'Ipadala'),
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onTap: _sending ? null : _send,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: blue),
                        child: _sending
                            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                            : Icon(Icons.arrow_upward_rounded, color: dark ? const Color(0xFF0B1B3A) : Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ]),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: hair, width: .5))),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Text(context.tr('This report is closed, so the chat is read only.', 'Sarado na ang ulat na ito, kaya basahin na lang ang chat.'), textAlign: TextAlign.center, style: caseInter(sub, 13, FontWeight.w500, 18)),
            ),
        ]),
      ),
    );
  }
}
