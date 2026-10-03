// SmartSumbong — History (branch B).
//
// Activity History, moved off Home into its own tab: the tanod's own
// dispatches from the past seven days, All / Responded / Missed, a
// responded one opening to show the field report and its photo/video
// proof. Same query, same rows and the same live reload as when it was a
// card on Home — only where it lives changed.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tanod_strings.dart';
import '../../theme.dart';
import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../../widgets/figma_ui.dart';
import '../widgets/tanod_nav_bar.dart';

/// Which half of Activity History a past dispatch belongs to.
///
/// Responded and Missed are not opinions — they are dispatch states.
/// accepted and resolved mean the tanod answered; expired means the
/// accept window elapsed with no response and 0006 alerted the admin.
/// A rerouted ticket is neither: it was answered, with a reason, and it
/// belongs in neither column.
enum ActivityKind { responded, missed }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_ActivityEntry> _activity = const [];
  bool _loading = true;
  String? _error;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('tanod-history-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dispatches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tanod_id',
          value: uid,
        ),
        callback: (_) {
          _liveDebounce?.cancel();
          _liveDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) _load();
          });
        },
      )
      ..subscribe();
  }

  Future<void> _load() async {
    // The last copy, at once (branch B).
    if (_loading) {
      final saved = await JsonCache.read('history');
      if (saved is List && mounted && _loading) {
        setState(() {
          _activity = [
            for (final r in saved)
              _ActivityEntry.fromRow(Map<String, dynamic>.from(r as Map)),
          ];
          _loading = false;
        });
      }
    }
    final hadSaved = !_loading;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      _subscribeLive(uid);

      // "In the past 7 days" per the frame. Carries field_report_text and
      // dispatch_media so a responded row can show what the tanod
      // actually submitted.
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 7))
          .toIso8601String();
      // No resident name: users_self_read is `id = auth.uid() or
      // is_admin()`, so a tanod cannot read anyone else's row. The ticket
      // number identifies the case without identifying a person.
      final past = await client
          .from('dispatches')
          .select('id, state, assigned_at, accepted_at, resolved_at, '
              'field_report_text, '
              'reports(tracking_id, subject, is_anonymous), '
              'dispatch_media(media_url, mime_type)')
          .eq('tanod_id', uid)
          .inFilter('state', ['accepted', 'resolved', 'expired'])
          .gte('assigned_at', since)
          .order('assigned_at', ascending: false);

      unawaited(JsonCache.write('history', past));
      if (!mounted) return;
      setState(() {
        _activity = [
          for (final r in past) _ActivityEntry.fromRow(r),
        ];
        _loading = false;
        _error = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.ts.homeLoadError(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      // No signal, but the saved history is showing: keep it.
      if (hadSaved) return;
      setState(() {
        _loading = false;
        _error = context.ts.homeLoadOffline;
      });
    }
  }

  // The title 28/800 at y=50 like every other tab, then the Activity
  // History card from the RESPONDED / MISSED frames at full height.
  // Branch D: the preview's History — the heading, the counts for the
  // past seven days, All / Responded / Missed as one segmented control,
  // and the entries as white cards (a responded one opens to the field
  // report and its proof).
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    return DPage(
      bottomBar: const TanodNavBar(current: TanodTab.history),
      child: RefreshIndicator(
        onRefresh: _load,
        color: d.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            DHeading(s.homeActivityHistory,
                lead: context.tr('Everything you responded to or missed in the past 7 days.',
                    'Lahat ng sinagot o nalampasan mo nitong nakaraang 7 araw.')),
            const SizedBox(height: 16),
            if (_error != null) ...[
              DSheet(
                borderColor: DColors.red.withValues(alpha: .5),
                child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
            ],
            _ActivityHistoryCard(loading: _loading, entries: _activity),
          ],
        ),
      ),
    );
  }
}

String _date(BuildContext context, DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${context.ts.monthFull(l.month)} ${l.day}, ${l.year}';
}

String _time(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final mm = l.minute.toString().padLeft(2, '0');
  return '$h:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
}

// ---------- activity history -------------------------------------
//
// Replaced 9 Sep 2026 (CAPSTONE G12 feedback): this card used to be
// "Alert History" — a tracking ID and a timestamp per row, nothing about
// what the tanod actually did. It carried no trace of a submitted update
// anywhere else in the app either. This is the same list of the tanod's
// own past dispatches, but a responded row now expands to show the
// field report text and any photo/video proof they attached — the same
// data submit_field_report() and dispatch_media already store, read
// back through RLS the tanod already has (dispatch_media_read admits
// `d.tanod_id = auth.uid()`).

class _ActivityEntry {
  _ActivityEntry({
    required this.kind,
    required this.who,
    required this.trackingId,
    required this.at,
    required this.reportText,
    required this.media,
  });

  final ActivityKind kind;
  final String who;
  final String trackingId;
  final DateTime? at;

  /// What the tanod wrote in submit_field_report(). Empty for a missed
  /// (expired) dispatch — nothing was ever submitted for those.
  final String reportText;
  final List<({String url, bool isVideo})> media;

  factory _ActivityEntry.fromRow(Map<String, dynamic> d) {
    final r = (d['reports'] ?? const {}) as Map<String, dynamic>;
    final subject = (r['subject'] as String? ?? '').trim();
    final ticket = r['tracking_id'] as String? ?? '';
    final missed = (d['state'] as String?) == 'expired';
    final rawMedia = (d['dispatch_media'] as List?) ?? const [];

    return _ActivityEntry(
      kind: missed ? ActivityKind.missed : ActivityKind.responded,
      who: subject.isEmpty ? ticket : '$ticket — $subject',
      trackingId: ticket,
      // A resolved dispatch reports back on when it was resolved, not
      // when it was first assigned — that is the moment the activity
      // actually happened. Missed and still-accepted rows have no
      // resolved_at, so they fall back to assigned_at as before.
      at: DateTime.tryParse((d['resolved_at'] ?? d['assigned_at']) as String? ?? ''),
      reportText: (d['field_report_text'] as String? ?? '').trim(),
      media: [
        for (final m in rawMedia)
          (
            url: (m as Map<String, dynamic>)['media_url'] as String,
            isVideo: isVideoMime(m['mime_type'] as String?),
          ),
      ],
    );
  }
}

class _ActivityHistoryCard extends StatefulWidget {
  const _ActivityHistoryCard({required this.loading, required this.entries});

  final bool loading;
  final List<_ActivityEntry> entries;

  @override
  State<_ActivityHistoryCard> createState() => _ActivityHistoryCardState();
}

class _ActivityHistoryCardState extends State<_ActivityHistoryCard> {
  ActivityKind? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final s = context.ts;
    final shown = _filter == null ? widget.entries : widget.entries.where((a) => a.kind == _filter).toList();
    final responded = widget.entries.where((a) => a.kind == ActivityKind.responded).length;
    final missed = widget.entries.where((a) => a.kind == ActivityKind.missed).length;
    Widget stat(String n, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.line)),
            child: Column(children: [
              Text(n, style: DType.mono(c, size: 22)),
              Text(label, style: DType.body(d.muted, size: 11.5)),
            ]),
          ),
        );
    Widget seg(String label, ActivityKind? k) {
      final on = _filter == k;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _filter = k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? d.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: DType.body(on ? d.bg : d.ink2, size: 13.5, w: FontWeight.w800)),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        stat('${widget.entries.length}', s.homeTabAll, d.ink),
        const SizedBox(width: 8),
        stat('$responded', s.homeTabResponded, d.dark ? const Color(0xFF5FD68A) : DColors.green),
        const SizedBox(width: 8),
        stat('$missed', s.homeTabMissed, d.dark ? const Color(0xFFFF8A8A) : DColors.red),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: d.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: d.line)),
        child: Row(children: [
          seg(s.homeTabAll, null),
          seg(s.homeTabResponded, ActivityKind.responded),
          seg(s.homeTabMissed, ActivityKind.missed),
        ]),
      ),
      const SizedBox(height: 12),
      if (widget.loading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
      else if (shown.isEmpty)
        DSheet(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Text(s.homeAlertHistoryEmpty, textAlign: TextAlign.center, style: DType.body(d.muted, size: 13)),
        )
      else
        for (final a in shown) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.line)),
            child: _ActivityRow(entry: a),
          ),
          const SizedBox(height: 10),
        ],
    ]);
  }
}

/// A responded entry expands to show the field report text and any
/// attached photo/video — the "activity" this card is now named for.
/// A missed entry has nothing to expand into (nothing was ever
/// submitted), so it stays a single row, same as before.
class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.entry});

  final _ActivityEntry entry;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final responded = entry.kind == ActivityKind.responded;
    final colour = responded ? _green : kFigmaRed;
    final expandable =
        responded && (entry.reportText.isNotEmpty || entry.media.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _open = !_open) : null,
            child: Row(
              children: [
                // Not handsets. The frame draws phone icons, which made
                // sense when these rows were imagined as calls — but
                // they are dispatch outcomes: accepted or resolved
                // against expired. Nobody phoned anyone, and an icon
                // that says otherwise is a small lie repeated on every
                // row.
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(
                    responded
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 19,
                    color: colour,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.who,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 21.84 / 14,
                          color: context.colors.navy,
                        ),
                      ),
                      Text(
                        _date(context, entry.at),
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                          height: 1.2,
                          color: context.colors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _time(entry.at),
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: context.colors.navy,
                  ),
                ),
                if (expandable) ...[
                  const SizedBox(width: 4),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: context.colors.muted),
                ],
              ],
            ),
          ),

          if (_open && expandable)
            Padding(
              padding: const EdgeInsets.only(left: 59, top: 4, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.reportText.isEmpty
                        ? context.ts.homeActivityNoText
                        : '${context.ts.homeActivityFieldReportLabel}'
                            '“${entry.reportText}”',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontStyle: entry.reportText.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: context.colors.navy),
                  ),
                  if (entry.media.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: entry.media.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) =>
                            _ActivityThumb(item: entry.media[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityThumb extends StatelessWidget {
  const _ActivityThumb({required this.item});

  final ({String url, bool isVideo}) item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (item.isVideo) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(url: item.url),
            ),
          );
        } else {
          showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: item.url),
              ),
            ),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: item.isVideo
            ? Container(
                width: 52,
                height: 52,
                color: Colors.black87,
                child: const Icon(Icons.play_circle_fill,
                    size: 24, color: Colors.white70),
              )
            : CachedNetworkImage(
                // A 52 thumbnail; the tap opens the original.
                imageUrl: cloudinarySized(item.url, width: 200),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 52,
                  height: 52,
                  color: context.colors.field,
                ),
                errorWidget: (_, _, _) => Container(
                  width: 52,
                  height: 52,
                  color: context.colors.field,
                  child: Icon(Icons.broken_image_outlined,
                      size: 18, color: context.colors.muted),
                ),
              ),
      ),
    );
  }
}

// ---------- shared bits ----------------------------------------

/// The frame's green (#058F00): View Details, Responded.
const _green = Color(0xFF058F00);


